## Tests for interactive planning and ask sessions.

import
  std/[algorithm, json, locks, os, osproc, sequtils, sha1, strformat, strutils, tables, tempfiles, times, unittest],
  jsony,
  scriptorium/[agent_runner, config, init, logging, orchestrator, ticket_metadata],
  helpers

suite "interactive planning":
  test "prompt assembly includes spec, history, and user message":
    let repoPath = "/tmp/repo"
    let spec = "# Spec\n\n- feature A\n"
    let history = @[
      PlanTurn(role: "engineer", text: "add feature B"),
      PlanTurn(role: "architect", text: "Added feature B to spec."),
    ]
    let userMsg = "add feature C"

    let planPath = "/tmp/plan-worktree"
    let prompt = buildInteractivePlanPrompt(repoPath, planPath, spec, history, userMsg)

    check repoPath in prompt
    check planPath in prompt
    check spec.strip() in prompt
    check "add feature B" in prompt
    check "Added feature B to spec." in prompt
    check "add feature C" in prompt
    check "AGENTS.md" in prompt
    check "Active working directory path (this is the scriptorium plan worktree):" in prompt
    check "Edit `spec.md` in this working directory." in prompt
    check "Treat `" in prompt
    check "as the authoritative planning file." in prompt
    check "If the engineer is discussing or asking questions, reply directly and do not edit spec.md." in prompt
    check "Only edit spec.md when the engineer asks to change plan content." in prompt
    check "Inline convenience copy of `spec.md` from the plan worktree:" in prompt

  test "turn commits when spec changes":
    let tmp = getTempDir() / "scriptorium_test_interactive_commit"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    var callCount = 0
    var capturedWorkingDir = ""
    var capturedPrompt = ""
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Write new content to spec.md and return a deterministic result.
      inc callCount
      capturedWorkingDir = req.workingDir
      capturedPrompt = req.prompt
      check req.heartbeatIntervalMs > 0
      check not req.onEvent.isNil
      req.onEvent(AgentStreamEvent(kind: agentEventReasoning, text: "reading spec", rawLine: ""))
      req.onEvent(AgentStreamEvent(kind: agentEventTool, text: "read_file (started)", rawLine: ""))
      writeFile(req.workingDir / "spec.md", "# Updated Spec\n\n- new item\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "Updated spec.",
        timeoutKind: "none",
      )

    var msgIdx = 0
    proc fakeInput(): string =
      ## Yield one message then raise EOFError.
      if msgIdx >= 1:
        raise newException(EOFError, "done")
      inc msgIdx
      result = "hello"

    runInteractivePlanSession(tmp, fakeRunner, fakeInput, quiet = true)

    let (logOutput, logRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " log --oneline scriptorium/plan"
    )
    check logRc == 0
    check "plan session turn 1" in logOutput
    check callCount == 1
    check capturedWorkingDir != tmp
    check tmp in capturedPrompt
    check "AGENTS.md" in capturedPrompt
    check capturedWorkingDir in capturedPrompt

  test "multi-turn plan session includes history and sequential commits":
    let tmp = getTempDir() / "scriptorium_test_interactive_multiturn"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    var callCount = 0
    var capturedPrompts: seq[string] = @[]
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Write different spec content on each call and capture the prompt.
      inc callCount
      capturedPrompts.add(req.prompt)
      let turnNum = callCount
      writeFile(req.workingDir / "spec.md", "# Spec v" & $turnNum & "\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "Architect response turn " & $turnNum,
        timeoutKind: "none",
      )

    var msgIdx = 0
    let messages = @["first user message", "second user message"]
    proc fakeInput(): string =
      ## Yield two messages then raise EOFError.
      if msgIdx >= messages.len:
        raise newException(EOFError, "done")
      result = messages[msgIdx]
      inc msgIdx

    runInteractivePlanSession(tmp, fakeRunner, fakeInput, quiet = true)

    check callCount == 2
    # Second prompt should contain first turn's user message and architect response.
    check "first user message" in capturedPrompts[1]
    check "Architect response turn 1" in capturedPrompts[1]
    # First prompt should not contain history from a prior turn.
    check "Architect response turn" notin capturedPrompts[0]

    let commits = latestPlanCommits(tmp, 10)
    check commits.anyIt("plan session turn 1" in it)
    check commits.anyIt("plan session turn 2" in it)

  test "turn makes no commit when spec unchanged":
    let tmp = getTempDir() / "scriptorium_test_interactive_no_commit"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Return a result without modifying spec.md.
      discard req
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "No changes needed.",
        timeoutKind: "none",
      )

    var msgIdx = 0
    proc fakeInput(): string =
      ## Yield one message then raise EOFError.
      if msgIdx >= 1:
        raise newException(EOFError, "done")
      inc msgIdx
      result = "hello"

    let before = planCommitCount(tmp)
    runInteractivePlanSession(tmp, fakeRunner, fakeInput, quiet = true)
    let after = planCommitCount(tmp)

    check after == before

  test "/show, /help, /quit do not invoke runner":
    let tmp = getTempDir() / "scriptorium_test_interactive_commands"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    var callCount = 0
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Count invocations; should never be called for slash commands.
      inc callCount
      discard req
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "",
        timeoutKind: "none",
      )

    let cmds = @["/show", "/help", "/quit"]
    var cmdIdx = 0
    proc fakeInput(): string =
      ## Yield slash commands in sequence, then EOF.
      if cmdIdx >= cmds.len:
        raise newException(EOFError, "done")
      result = cmds[cmdIdx]
      inc cmdIdx

    runInteractivePlanSession(tmp, fakeRunner, fakeInput, quiet = true)

    check callCount == 0

  test "/exit exits session without invoking runner":
    let tmp = getTempDir() / "scriptorium_test_interactive_exit"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    var callCount = 0
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Count invocations; should never be called when /exit is used.
      inc callCount
      discard req
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "",
        timeoutKind: "none",
      )

    var cmdIdx = 0
    proc fakeInput(): string =
      ## Yield /exit then EOF.
      if cmdIdx >= 1:
        raise newException(EOFError, "done")
      inc cmdIdx
      result = "/exit"

    runInteractivePlanSession(tmp, fakeRunner, fakeInput, quiet = true)

    check callCount == 0

  test "unknown slash commands rejected without invoking runner":
    let tmp = getTempDir() / "scriptorium_test_interactive_unknown_cmd"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    var callCount = 0
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Count invocations; should never be called for unknown slash commands.
      inc callCount
      discard req
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "",
        timeoutKind: "none",
      )

    let cmds = @["/foo", "/quit"]
    var cmdIdx = 0
    proc fakeInput(): string =
      ## Yield unknown slash command then quit.
      if cmdIdx >= cmds.len:
        raise newException(EOFError, "done")
      result = cmds[cmdIdx]
      inc cmdIdx

    let before = planCommitCount(tmp)
    runInteractivePlanSession(tmp, fakeRunner, fakeInput, quiet = true)
    let after = planCommitCount(tmp)

    check callCount == 0
    check after == before

  test "turn reverts writes outside spec.md":
    let tmp = getTempDir() / "scriptorium_test_interactive_out_of_scope"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Write one out-of-scope file that should be reverted.
      writeFile(req.workingDir / "spec.md", "# Updated Spec\n")
      writeFile(req.workingDir / "areas/02-out-of-scope.md", "# Nope\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "done",
        timeoutKind: "none",
      )

    var msgIdx = 0
    proc fakeInput(): string =
      ## Yield one message then raise EOFError.
      if msgIdx >= 1:
        raise newException(EOFError, "done")
      inc msgIdx
      result = "hello"

    let before = planCommitCount(tmp)
    runInteractivePlanSession(tmp, fakeRunner, fakeInput, quiet = true)
    let after = planCommitCount(tmp)
    let files = planTreeFiles(tmp)

    check after > before
    check "areas/02-out-of-scope.md" notin files

  test "interrupt-style input exits session cleanly":
    let tmp = getTempDir() / "scriptorium_test_interactive_interrupt"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    var runnerCalls = 0
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Track runner invocations; interrupted input should stop before agent calls.
      inc runnerCalls
      discard req
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "",
        timeoutKind: "none",
      )

    var inputCalls = 0
    proc fakeInput(): string =
      ## Simulate interrupted terminal input.
      inc inputCalls
      raise newException(IOError, "interrupted by signal")

    let before = planCommitCount(tmp)
    runInteractivePlanSession(tmp, fakeRunner, fakeInput, quiet = true)
    let after = planCommitCount(tmp)

    check inputCalls == 1
    check runnerCalls == 0
    check after == before

suite "interactive ask session":
  test "ask prompt includes read-only instruction and spec":
    let tmp = getTempDir() / "scriptorium_test_ask_prompt"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    let prompt = buildInteractiveAskPrompt(tmp, tmp, "# My Spec\n", @[], "what is this?")
    check "read-only" in prompt.toLowerAscii()
    check "Do NOT edit any files" in prompt
    check "# My Spec" in prompt
    check "what is this?" in prompt
    check "AGENTS.md" in prompt

  test "ask prompt includes conversation history":
    let tmp = getTempDir() / "scriptorium_test_ask_history"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    let history = @[
      PlanTurn(role: "engineer", text: "hello"),
      PlanTurn(role: "architect", text: "hi there"),
    ]
    let prompt = buildInteractiveAskPrompt(tmp, tmp, "# Spec\n", history, "follow up")
    check "[engineer]: hello" in prompt
    check "[architect]: hi there" in prompt
    check "follow up" in prompt

  test "ask session invokes runner and records history":
    let tmp = getTempDir() / "scriptorium_test_ask_session"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    var callCount = 0
    var capturedPrompt = ""
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Return a response without modifying any files.
      inc callCount
      capturedPrompt = req.prompt
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "The spec describes a CLI tool.",
        timeoutKind: "none",
      )

    var msgIdx = 0
    proc fakeInput(): string =
      ## Yield one message then raise EOFError.
      if msgIdx >= 1:
        raise newException(EOFError, "done")
      inc msgIdx
      result = "what does the spec say?"

    runInteractiveAskSession(tmp, fakeRunner, fakeInput, quiet = true)

    check callCount == 1
    check "what does the spec say?" in capturedPrompt
    check "read-only" in capturedPrompt.toLowerAscii()

  test "ask session makes no commits":
    let tmp = getTempDir() / "scriptorium_test_ask_no_commit"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Return a response without modifying any files.
      discard req
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "Here is my answer.",
        timeoutKind: "none",
      )

    var msgIdx = 0
    proc fakeInput(): string =
      if msgIdx >= 1:
        raise newException(EOFError, "done")
      inc msgIdx
      result = "tell me about the project"

    let before = planCommitCount(tmp)
    runInteractiveAskSession(tmp, fakeRunner, fakeInput, quiet = true)
    let after = planCommitCount(tmp)

    check after == before

  test "ask session rejects writes":
    let tmp = getTempDir() / "scriptorium_test_ask_rejects_writes"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Attempt to write a file, which should be rejected.
      writeFile(req.workingDir / "spec.md", "# Modified Spec\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "I edited the spec.",
        timeoutKind: "none",
      )

    var msgIdx = 0
    proc fakeInput(): string =
      if msgIdx >= 1:
        raise newException(EOFError, "done")
      inc msgIdx
      result = "tell me something"

    let before = planCommitCount(tmp)
    expect ValueError:
      runInteractiveAskSession(tmp, fakeRunner, fakeInput, quiet = true)
    let after = planCommitCount(tmp)
    check after == before

  test "unknown slash commands rejected without invoking runner in ask mode":
    let tmp = getTempDir() / "scriptorium_test_ask_unknown_cmd"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    var callCount = 0
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Count invocations; should never be called for unknown slash commands.
      inc callCount
      discard req
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "",
        timeoutKind: "none",
      )

    let cmds = @["/unknown", "/quit"]
    var cmdIdx = 0
    proc fakeInput(): string =
      ## Yield unknown slash command then quit.
      if cmdIdx >= cmds.len:
        raise newException(EOFError, "done")
      result = cmds[cmdIdx]
      inc cmdIdx

    let before = planCommitCount(tmp)
    runInteractiveAskSession(tmp, fakeRunner, fakeInput, quiet = true)
    let after = planCommitCount(tmp)

    check callCount == 0
    check after == before

  test "/exit exits ask session without invoking runner":
    let tmp = getTempDir() / "scriptorium_test_ask_exit"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    var callCount = 0
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Count invocations; should never be called when /exit is used.
      inc callCount
      discard req
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "",
        timeoutKind: "none",
      )

    var cmdIdx = 0
    proc fakeInput(): string =
      ## Yield /exit then EOF.
      if cmdIdx >= 1:
        raise newException(EOFError, "done")
      inc cmdIdx
      result = "/exit"

    runInteractiveAskSession(tmp, fakeRunner, fakeInput, quiet = true)

    check callCount == 0

  test "/show, /help, /quit do not invoke runner in ask mode":
    let tmp = getTempDir() / "scriptorium_test_ask_commands"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    var callCount = 0
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      inc callCount
      discard req
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "",
        timeoutKind: "none",
      )

    let cmds = @["/show", "/help", "/quit"]
    var cmdIdx = 0
    proc fakeInput(): string =
      if cmdIdx >= cmds.len:
        raise newException(EOFError, "done")
      result = cmds[cmdIdx]
      inc cmdIdx

    runInteractiveAskSession(tmp, fakeRunner, fakeInput, quiet = true)

    check callCount == 0
