## Tests for orchestrator end-to-end flow, interactive sessions, concurrent execution.

import
  std/[algorithm, json, locks, os, osproc, sequtils, sha1, strformat, strutils, tables, tempfiles, times, unittest],
  jsony,
  scriptorium/[agent_runner, config, init, logging, orchestrator, ticket_metadata],
  helpers

suite "orchestrator final v1 flow":
  setup:
    resetRateLimitState()
    while consumeSubmitPrSummary() != "": discard

  test "blank spec tick skips orchestration and does not invoke agents":
    let tmp = getTempDir() / "scriptorium_test_v1_36_blank_spec_guard"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    writeOrchestratorEndpointConfig(tmp, 21)

    var callCount = 0
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Count calls to verify no architect/manager/coding runner executes.
      inc callCount
      discard request
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "",
        timeoutKind: "none",
      )

    runOrchestratorForTicks(tmp, 1, fakeRunner)

    check callCount == 0

  test "no-spec WAITING message logs INFO once then DEBUG on subsequent ticks":
    let tmp = getTempDir() / "scriptorium_test_spec_waiting_dedup"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    writeOrchestratorEndpointConfig(tmp, 23)

    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## No-op runner; spec is blank so nothing should run.
      discard request
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "",
        timeoutKind: "none",
      )

    captureLogs = true
    capturedLogs = @[]
    defer: captureLogs = false

    runOrchestratorForTicks(tmp, 3, fakeRunner)

    let waitingInfoLogs = capturedLogs.filterIt(
      it.level == lvlInfo and "WAITING: no spec" in it.msg
    )
    let waitingDebugLogs = capturedLogs.filterIt(
      it.level == lvlDebug and "WAITING: no spec" in it.msg
    )
    check waitingInfoLogs.len == 1
    check waitingDebugLogs.len == 2

  test "integration-test failure on master blocks assignment of open tickets":
    let tmp = getTempDir() / "scriptorium_test_master_red_integration"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addIntegrationFailingMakefile(tmp)
    writeSpecInPlan(tmp, "# Spec\n\nNeed assignment.\n")
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    runOrchestratorForTicks(tmp, 1, noopRunner)

    let files = planTreeFiles(tmp)
    check "tickets/open/0001-first.md" in files
    check "tickets/in-progress/0001-first.md" notin files

  test "runArchitectAreas commits files written by mocked architect runner":
    let tmp = getTempDir() / "scriptorium_test_v1_37_run_architect_areas"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    writeSpecInPlan(tmp, "# Spec\n\nBuild area files.\n")
    var writtenCfg = defaultConfig()
    writtenCfg.agents.architect.reasoningEffort = "high"
    writeScriptoriumConfig(tmp, writtenCfg)

    var callCount = 0
    var capturedRequest = AgentRunRequest()
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Write one area file directly into areas/ from the plan worktree.
      inc callCount
      capturedRequest = request
      writeFile(request.workingDir / "areas/01-arch.md", "# Area 01\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "areas written",
        timeoutKind: "none",
      )

    let before = planCommitCount(tmp)
    let changed = runArchitectAreas(tmp, fakeRunner)
    let after = planCommitCount(tmp)
    let files = planTreeFiles(tmp)

    check changed
    check callCount == 1
    check capturedRequest.ticketId == "run"
    check capturedRequest.model == resolveModel("claude-opus-4-6")
    check capturedRequest.reasoningEffort == "high"
    check capturedRequest.logRoot == tmp / ".scriptorium" / "logs" / "architect" / "areas"
    check tmp in capturedRequest.prompt
    check "AGENTS.md" in capturedRequest.prompt
    check "Active working directory path (this is the scriptorium plan worktree):" in capturedRequest.prompt
    check "Read `spec.md` in this working directory and write/update area markdown files directly under `areas/` in this working directory." in capturedRequest.prompt
    check "areas/01-arch.md" in files
    check after == before + 2  # areas commit + spec hash marker commit

  test "done tickets suppress areas from areasNeedingTickets":
    let tmp = getTempDir() / "scriptorium_test_done_ticket_suppression"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addAreaToPlan(tmp, "01-done-area.md", "# Area 01\n")
    addAreaToPlan(tmp, "02-pending-area.md", "# Area 02\n")
    addTicketToPlan(tmp, "done", "0001-done-area-summary.md", "# Done\n\n**Area:** 01-done-area\n")

    let needed = areasNeedingTickets(tmp)
    check "areas/02-pending-area.md" in needed
    check "areas/01-done-area.md" notin needed

  test "done ticket with unchanged area hash suppresses area":
    let tmp = getTempDir() / "scriptorium_test_done_unchanged_hash"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addAreaToPlan(tmp, "01-done-area.md", "# Area 01\n")
    addAreaToPlan(tmp, "02-pending-area.md", "# Area 02\n")
    addTicketToPlan(tmp, "done", "0001-done-area-summary.md", "# Done\n\n**Area:** 01-done-area\n")
    # Write area hashes matching current content
    var hashes = initTable[string, string]()
    hashes["01-done-area"] = $secureHash("# Area 01\n")
    hashes["02-pending-area"] = $secureHash("# Area 02\n")
    writeAreaHashesInPlan(tmp, hashes)

    let needed = areasNeedingTickets(tmp)
    check needed.len == 0  # both areas have matching hashes, done area not re-triggered

  test "done ticket with changed area content triggers new tickets":
    let tmp = getTempDir() / "scriptorium_test_done_changed_hash"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addAreaToPlan(tmp, "01-done-area.md", "# Area 01 v2\n")  # content differs from stored hash
    addAreaToPlan(tmp, "02-unchanged.md", "# Area 02\n")
    addTicketToPlan(tmp, "done", "0001-done-area-summary.md", "# Done\n\n**Area:** 01-done-area\n")
    # Write area hashes with old content hash for 01-done-area
    var hashes = initTable[string, string]()
    hashes["01-done-area"] = $secureHash("# Area 01 v1\n")  # old hash
    hashes["02-unchanged"] = $secureHash("# Area 02\n")  # matching hash
    writeAreaHashesInPlan(tmp, hashes)

    let needed = areasNeedingTickets(tmp)
    check "areas/01-done-area.md" in needed  # changed content triggers new tickets
    check "areas/02-unchanged.md" notin needed  # unchanged is suppressed

  test "open ticket blocks area even when content changed":
    let tmp = getTempDir() / "scriptorium_test_open_blocks_changed"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addAreaToPlan(tmp, "01-active.md", "# Area 01 v2\n")
    addTicketToPlan(tmp, "open", "0001-active-ticket.md", "# Ticket\n\n**Area:** 01-active\n")
    var hashes = initTable[string, string]()
    hashes["01-active"] = $secureHash("# Area 01 v1\n")  # old hash, content changed
    writeAreaHashesInPlan(tmp, hashes)

    let needed = areasNeedingTickets(tmp)
    check "areas/01-active.md" notin needed  # open ticket blocks regardless of content change

  test "architect creates spec hash marker on first run":
    let tmp = getTempDir() / "scriptorium_test_arch_spec_hash_first_run"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    writeSpecInPlan(tmp, "# Spec\n\nBuild a CLI tool.\n")

    proc generator(model: string, spec: string): seq[AreaDocument] =
      result = @[AreaDocument(path: "01-cli.md", content: "# CLI Area\n")]

    let synced = syncAreasFromSpec(tmp, generator)
    check synced

    let files = planTreeFiles(tmp)
    check "areas/.spec-hash" in files
    let hashContent = readPlanFile(tmp, "areas/.spec-hash").strip()
    check hashContent == $secureHash("# Spec\n\nBuild a CLI tool.\n")

  test "architect skips when spec unchanged":
    let tmp = getTempDir() / "scriptorium_test_arch_skip_unchanged"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    let specContent = "# Spec\n\nBuild a CLI tool.\n"
    writeSpecInPlan(tmp, specContent)
    addAreaToPlan(tmp, "01-cli.md", "# CLI Area\n")
    writeSpecHashInPlan(tmp, $secureHash(specContent))

    var callCount = 0
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      inc callCount
      result = AgentRunResult(backend: harnessClaudeCode, exitCode: 0, attempt: 1, attemptCount: 1)

    let changed = runArchitectAreas(tmp, fakeRunner)
    check not changed
    check callCount == 0  # architect was not invoked

  test "architect re-runs when spec changes":
    let tmp = getTempDir() / "scriptorium_test_arch_rerun_spec_changed"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    let oldSpec = "# Spec\n\nBuild a CLI tool.\n"
    writeSpecInPlan(tmp, "# Spec\n\nBuild a CLI tool with logging.\n")  # new content
    addAreaToPlan(tmp, "01-cli.md", "# CLI Area\n")
    writeSpecHashInPlan(tmp, $secureHash(oldSpec))  # hash of old spec

    var callCount = 0
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      inc callCount
      # Simulate architect writing an updated area
      writeFile(request.workingDir / "areas/02-logging.md", "# Logging Area\n")
      result = AgentRunResult(backend: harnessClaudeCode, exitCode: 0, attempt: 1, attemptCount: 1)

    let changed = runArchitectAreas(tmp, fakeRunner)
    check changed
    check callCount == 1

    let files = planTreeFiles(tmp)
    check "areas/02-logging.md" in files
    check "areas/.spec-hash" in files

  test "migration writes spec hash marker for existing areas without re-running":
    let tmp = getTempDir() / "scriptorium_test_arch_migration"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    let specContent = "# Spec\n\nExisting project.\n"
    writeSpecInPlan(tmp, specContent)
    addAreaToPlan(tmp, "01-cli.md", "# CLI Area\n")
    # No .spec-hash file — simulates pre-upgrade state

    var callCount = 0
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      inc callCount
      result = AgentRunResult(backend: harnessClaudeCode, exitCode: 0, attempt: 1, attemptCount: 1)

    let changed = runArchitectAreas(tmp, fakeRunner)
    check not changed  # migration only, no architect run
    check callCount == 0

    let files = planTreeFiles(tmp)
    check "areas/.spec-hash" in files  # marker was written
    let hashContent = readPlanFile(tmp, "areas/.spec-hash").strip()
    check hashContent == $secureHash(specContent)

  test "runOrchestratorForTicks drives spec to done in one bounded tick with mocked runners":
    let tmp = getTempDir() / "scriptorium_test_v1_39_full_cycle_tick"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    writeSpecInPlan(tmp, "# Spec\n\nDeliver one full-flow ticket.\n")
    writeOrchestratorEndpointConfig(tmp, 22)
    var cfg = loadConfig(tmp)
    cfg.concurrency.maxAgents = 1
    writeScriptoriumConfig(tmp, cfg)

    var callOrder: seq[string] = @[]
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Emulate architect, manager, and coding agent by ticketId role markers.
      callOrder.add(request.ticketId)
      case request.ticketId
      of "run":
        writeFile(
          request.workingDir / "areas/01-full-flow.md",
          "# Area 01\n\n## Goal\n- Full flow.\n",
        )
        result = AgentRunResult(
          backend: harnessCodex,
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          lastMessage: "areas done",
          timeoutKind: "none",
        )
      of "manager-01-full-flow":
        result = AgentRunResult(
          backend: harnessCodex,
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          lastMessage: "```markdown\n# Full Flow\n\n**Area:** 01-full-flow\n```",
          timeoutKind: "none",
        )
      of "0001-prediction":
        result = AgentRunResult(
          backend: harnessCodex,
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          lastMessage: """{"predicted_difficulty": "easy", "predicted_duration_minutes": 10, "reasoning": "Simple ticket."}""",
          timeoutKind: "none",
        )
      of "0001":
        writeFile(request.workingDir / "flow-output.txt", "done\n")
        runCmdOrDie("git -C " & quoteShell(request.workingDir) & " add flow-output.txt")
        runCmdOrDie("git -C " & quoteShell(request.workingDir) & " commit -m test-v1-39-flow-output")
        callSubmitPrTool("ship flow")
        result = AgentRunResult(
          backend: harnessCodex,
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          lastMessage: "Done.",
          timeoutKind: "none",
        )
      else:
        raise newException(ValueError, "unexpected runner ticket id: " & request.ticketId)

    runOrchestratorForTicks(tmp, 1, fakeRunner)

    let files = planTreeFiles(tmp)
    check callOrder == @["run", "manager-01-full-flow", "0001-prediction", "0001"]
    check "areas/01-full-flow.md" in files
    check "tickets/done/0001-full-flow.md" in files
    check "tickets/open/0001-full-flow.md" notin files
    check "tickets/in-progress/0001-full-flow.md" notin files
    check "queue/merge/pending/0001-0001.md" notin files

    let (masterFile, masterRc) = execCmdEx("git -C " & quoteShell(tmp) & " show master:flow-output.txt")
    check masterRc == 0
    check masterFile.strip() == "done"

    validateTicketStateInvariant(tmp)
    validateTransitionCommitInvariant(tmp)

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
    check "Only edit spec.md in this working directory." in prompt
    check "Treat `" in prompt
    check "as the authoritative planning file." in prompt
    check "If the engineer is discussing or asking questions, reply directly and do not edit spec.md." in prompt
    check "Only edit spec.md when the engineer asks to change plan content." in prompt
    check "Inline convenience copy of `spec.md` from the plan worktree:" in prompt

  test "turn commits when spec changes":
    let tmp = getTempDir() / "scriptorium_test_interactive_commit"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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

  test "turn rejects writes outside spec.md":
    let tmp = getTempDir() / "scriptorium_test_interactive_out_of_scope"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Write one out-of-scope file in the plan worktree.
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
    expect ValueError:
      runInteractivePlanSession(tmp, fakeRunner, fakeInput, quiet = true)
    let after = planCommitCount(tmp)
    let files = planTreeFiles(tmp)

    check after == before
    check "areas/02-out-of-scope.md" notin files

  test "interrupt-style input exits session cleanly":
    let tmp = getTempDir() / "scriptorium_test_interactive_interrupt"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    let prompt = buildInteractiveAskPrompt(tmp, tmp, "# My Spec\n", @[], "what is this?")
    check "read-only" in prompt.toLowerAscii()
    check "Do NOT edit any files" in prompt
    check "# My Spec" in prompt
    check "what is this?" in prompt
    check "AGENTS.md" in prompt

  test "ask prompt includes conversation history":
    let tmp = getTempDir() / "scriptorium_test_ask_history"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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

suite "orchestrator agent enqueue with fakes":
  setup:
    resetRateLimitState()
    while consumeSubmitPrSummary() != "": discard

  test "agent run enqueues exactly one merge request with metadata":
    withTempRepo("scriptorium_test_enqueue_metadata_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      addPassingMakefile(repoPath)
      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

      let assignment = assignOldestOpenTicket(repoPath)
      proc fakeRunner(request: AgentRunRequest): AgentRunResult =
        ## Return a deterministic run output and signal submit_pr through MCP.
        discard request
        callSubmitPrTool("ship it")
        result = AgentRunResult(
          backend: harnessCodex,
          command: @["codex", "exec"],
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          stdout: "",
          logFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.jsonl",
          lastMessageFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.last_message.txt",
          lastMessage: "Done.",
          timeoutKind: "none",
        )

      discard executeAssignedTicket(repoPath, assignment, fakeRunner)

      let queueFiles = pendingQueueFiles(repoPath)
      check queueFiles.len == 1
      check queueFiles[0] == "queue/merge/pending/0001-0001.md"

      let queueEntry = readPlanFile(repoPath, queueFiles[0])
      check "**Ticket:** tickets/in-progress/0001-first.md" in queueEntry
      check "**Ticket ID:** 0001" in queueEntry
      check "**Summary:** ship it" in queueEntry
      check "**Branch:** scriptorium/ticket-0001" in queueEntry
      check ("**Worktree:** " & assignment.worktree) in queueEntry
    )

  test "orchestrator tick assigns and executes before merge queue processing":
    withTempRepo("scriptorium_test_tick_assign_execute_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      addPassingMakefile(repoPath)
      writeSpecInPlan(repoPath, "# Spec\n\nDrive orchestrator tick.\n")
      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
      addTicketToPlan(repoPath, "open", "0002-second.md", "# Ticket 2\n\n**Area:** b\n")

      let firstAssignment = assignOldestOpenTicket(repoPath)
      writeFile(firstAssignment.worktree / "ticket-output.txt", "done\n")
      runCmdOrDie("git -C " & quoteShell(firstAssignment.worktree) & " add ticket-output.txt")
      runCmdOrDie("git -C " & quoteShell(firstAssignment.worktree) & " commit -m ticket-output")
      discard enqueueMergeRequest(repoPath, firstAssignment, "first summary")

      proc fakeRunner(request: AgentRunRequest): AgentRunResult =
        ## Ticket 0002 returns without submit_pr so it gets reopened as stalled.
        if request.ticketId == "run":
          return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
        elif request.ticketId.startsWith("manager"):
          return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
        elif request.ticketId.endsWith("-prediction"):
          return AgentRunResult(exitCode: 1, attemptCount: 1, stdout: "")
        else:
          return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "", lastMessage: "ok", timeoutKind: "none")

      writeOrchestratorEndpointConfig(repoPath, 0)
      runOrchestratorForTicks(repoPath, 1, fakeRunner)

      let files = planTreeFiles(repoPath)
      check "tickets/done/0001-first.md" in files
      check "tickets/open/0002-second.md" in files
      check pendingQueueFiles(repoPath).len == 0

      let commits = latestPlanCommits(repoPath, 20)
      check commits.anyIt(it == "scriptorium: complete ticket 0001")
      check commits.anyIt(it == "scriptorium: review ticket 0001")
      check commits.anyIt(it.startsWith("scriptorium: reopen failed ticket"))
      check commits.anyIt(it == "scriptorium: record agent run 0002-second")
      check commits.anyIt(it == "scriptorium: assign ticket 0002-second")
    )

  test "end-to-end happy path from spec to done":
    withTempRepo("scriptorium_test_e2e_happy_path_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      addPassingMakefile(repoPath)

      var architectCalls = 0
      proc architectGenerator(model: string, spec: string): seq[AreaDocument] =
        ## Return one deterministic area document from spec input.
        inc architectCalls
        check model == resolveModel("claude-opus-4-6")
        check "scriptorium plan" in spec
        result = @[
          AreaDocument(
            path: "01-e2e.md",
            content: "# Area 01\n\n## Goal\n- Validate V1 happy path.\n",
          )
        ]

      let syncedAreas = syncAreasFromSpec(repoPath, architectGenerator)
      check syncedAreas
      check architectCalls == 1

      addTicketToPlan(repoPath, "open", "0001-e2e-happy-path.md",
        "# Ticket 1\n\nImplement end-to-end flow.\n\n**Area:** 01-e2e\n")

      let filesAfterPlanning = planTreeFiles(repoPath)
      check "areas/01-e2e.md" in filesAfterPlanning
      check "tickets/open/0001-e2e-happy-path.md" in filesAfterPlanning

      let assignment = assignOldestOpenTicket(repoPath)
      check assignment.inProgressTicket == "tickets/in-progress/0001-e2e-happy-path.md"
      writeFile(assignment.worktree / "e2e-output.txt", "done\n")
      runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add e2e-output.txt")
      runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m test-e2e-ticket-output")
      let (ticketHead, ticketHeadRc) = execCmdEx("git -C " & quoteShell(assignment.worktree) & " rev-parse HEAD")
      doAssert ticketHeadRc == 0

      proc fakeRunner(request: AgentRunRequest): AgentRunResult =
        ## Return a deterministic successful output and request merge submission.
        discard request
        callSubmitPrTool("ship e2e")
        result = AgentRunResult(
          backend: harnessCodex,
          command: @["codex", "exec"],
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          stdout: "",
          logFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.jsonl",
          lastMessageFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.last_message.txt",
          lastMessage: "Done.",
          timeoutKind: "none",
        )

      discard executeAssignedTicket(repoPath, assignment, fakeRunner)
      let pending = pendingQueueFiles(repoPath)
      check pending.len == 1
      check pending[0] == "queue/merge/pending/0001-0001.md"

      let processed = processMergeQueue(repoPath, noopRunner)
      check processed
      check pendingQueueFiles(repoPath).len == 0

      let finalFiles = planTreeFiles(repoPath)
      check "tickets/done/0001-e2e-happy-path.md" in finalFiles
      check "tickets/open/0001-e2e-happy-path.md" notin finalFiles
      check "tickets/in-progress/0001-e2e-happy-path.md" notin finalFiles

      let (masterOutput, masterRc) = execCmdEx("git -C " & quoteShell(repoPath) & " show master:e2e-output.txt")
      check masterRc == 0
      check masterOutput.strip() == "done"

      let (_, ancestorRc) = execCmdEx(
        "git -C " & quoteShell(repoPath) & " merge-base --is-ancestor " & ticketHead.strip() & " master"
      )
      check ancestorRc == 0

      validateTicketStateInvariant(repoPath)
      validateTransitionCommitInvariant(repoPath)
    )

  test "one-shot plan runner reads repo path context and commits spec only":
    withTempRepo("scriptorium_test_oneshot_plan_runner_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      writeFile(repoPath / "source-marker.txt", "integration-marker\n")
      runCmdOrDie("git -C " & quoteShell(repoPath) & " add source-marker.txt")
      runCmdOrDie("git -C " & quoteShell(repoPath) & " commit -m test-add-source-marker")

      var callCount = 0
      var capturedPrompt = ""
      var capturedRepoPath = ""
      proc fakeRunner(request: AgentRunRequest): AgentRunResult =
        ## Read the repo path from prompt context and update spec.md in plan worktree.
        inc callCount
        capturedPrompt = request.prompt
        let repoPathMarker = "Project repository root path (read project source files and instructions from here):\n"
        let markerIndex = request.prompt.find(repoPathMarker)
        doAssert markerIndex >= 0
        let pathStart = markerIndex + repoPathMarker.len
        let pathEnd = request.prompt.find('\n', pathStart)
        doAssert pathEnd > pathStart
        let repoPathFromPrompt = request.prompt[pathStart..<pathEnd].strip()
        capturedRepoPath = repoPathFromPrompt
        let marker = readFile(repoPathFromPrompt / "source-marker.txt").strip()
        writeFile(request.workingDir / "spec.md", "# Integration Spec\n\n- marker: " & marker & "\n")

        result = AgentRunResult(
          backend: harnessCodex,
          command: @["codex", "exec"],
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          stdout: "",
          logFile: request.workingDir / ".scriptorium/logs/architect/spec/attempt-01.jsonl",
          lastMessageFile: request.workingDir / ".scriptorium/logs/architect/spec/attempt-01.last_message.txt",
          lastMessage: "Updated spec",
          timeoutKind: "none",
        )

      let changed = updateSpecFromArchitect(repoPath, "sync source marker", fakeRunner)

      check changed
      check callCount == 1
      check capturedRepoPath == repoPath
      check "AGENTS.md" in capturedPrompt
      check "Active working directory path (this is the scriptorium plan worktree):" in capturedPrompt
      check "Only edit spec.md in this working directory." in capturedPrompt
      check "as the authoritative planning file." in capturedPrompt
      check "Inline convenience copy of `spec.md` from the plan worktree:" in capturedPrompt

      let specBody = readPlanFile(repoPath, "spec.md")
      check "# Integration Spec" in specBody
      check "- marker: integration-marker" in specBody

      let files = planTreeFiles(repoPath)
      check "spec.md" in files
      check "areas/01-out-of-scope.md" notin files

      let commits = latestPlanCommits(repoPath, 1)
      check commits.len == 1
      check commits[0] == "scriptorium: update spec from architect"
    )

suite "non-blocking tick loop":
  setup:
    resetRateLimitState()
    while consumeSubmitPrSummary() != "": discard
    discard consumeReviewDecision()

  test "serial mode executes one ticket per tick when maxAgents is 1":
    let tmp = getTempDir() / "scriptorium_test_serial_tick"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    writeSpecInPlan(tmp, "# Spec\n\nSerial test.\n")
    addTicketToPlan(tmp, "open", "0001-serial.md", "# Ticket 1\n\n**Area:** a\n")

    var codingCalled = false
    let fakeRunner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      if request.ticketId == "run":
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId.startsWith("manager"):
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId == "0001-prediction":
        return AgentRunResult(exitCode: 1, attemptCount: 1, stdout: "")
      elif request.ticketId == "0001":
        codingCalled = true
        recordSubmitPrSummary("serial done", "0001")
        return AgentRunResult(exitCode: 0, attemptCount: 1, lastMessage: "Done.", timeoutKind: "none")
      else:
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "", timeoutKind: "none")

    var cfg = defaultConfig()
    cfg.concurrency.maxAgents = 1
    writeScriptoriumConfig(tmp, cfg)

    runOrchestratorForTicks(tmp, 1, fakeRunner)

    check codingCalled
    let files = planTreeFiles(tmp)
    # Serial mode: ticket submitted and merged in the same tick.
    check "tickets/done/0001-serial.md" in files
    check "tickets/open/0001-serial.md" notin files

suite "concurrent agent execution":
  setup:
    resetRateLimitState()
    while consumeSubmitPrSummary() != "": discard

  test "two agents run concurrently in separate worktrees without interfering":
    let tmp = getTempDir() / "scriptorium_test_concurrent_agents"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    writeSpecInPlan(tmp, "# Spec\n\nConcurrent test.\n")
    addTicketToPlan(tmp, "open", "0001-alpha.md", "# Ticket Alpha\n\n**Area:** area-a\n")
    addTicketToPlan(tmp, "open", "0002-beta.md", "# Ticket Beta\n\n**Area:** area-b\n")

    var cfg = defaultConfig()
    cfg.concurrency.maxAgents = 2
    writeScriptoriumConfig(tmp, cfg)

    var codingCallCount = 0
    var codingCallLock: Lock
    initLock(codingCallLock)
    var seenTickets: seq[string] = @[]

    let fakeRunner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      if request.ticketId == "run":
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId.startsWith("manager"):
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId.endsWith("-prediction"):
        return AgentRunResult(exitCode: 1, attemptCount: 1, stdout: "")
      elif request.ticketId == "0001" or request.ticketId == "0002":
        {.cast(gcsafe).}:
          acquire(codingCallLock)
          inc codingCallCount
          seenTickets.add(request.ticketId)
          release(codingCallLock)
        recordSubmitPrSummary("done " & request.ticketId, request.ticketId)
        return AgentRunResult(exitCode: 0, attemptCount: 1, lastMessage: "Done.", timeoutKind: "none")
      else:
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "", timeoutKind: "none")

    runOrchestratorForTicks(tmp, 3, fakeRunner)

    acquire(codingCallLock)
    let finalCount = codingCallCount
    let finalTickets = seenTickets
    release(codingCallLock)
    deinitLock(codingCallLock)

    check finalCount == 2
    check "0001" in finalTickets
    check "0002" in finalTickets

    let files = planTreeFiles(tmp)
    check "tickets/open/0001-alpha.md" notin files
    check "tickets/open/0002-beta.md" notin files

  test "submit_pr correctly identifies calling agent ticket in parallel mode":
    let tmp = getTempDir() / "scriptorium_test_concurrent_submit_pr"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** area-x\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** area-y\n")

    let assignment1 = assignOldestOpenTicket(tmp)
    let assignment2 = assignOldestOpenTicket(tmp)
    check assignment1.inProgressTicket.len > 0
    check assignment2.inProgressTicket.len > 0

    setActiveTicketWorktree(assignment1.worktree, "0001")
    setActiveTicketWorktree(assignment2.worktree, "0002")
    defer: clearActiveTicketWorktree()

    let httpServer = createOrchestratorServer()
    let submitPrHandler = httpServer.server.toolHandlers["submit_pr"]

    discard submitPrHandler(%*{"summary": "done ticket 1", "ticket_id": "0001"})
    discard submitPrHandler(%*{"summary": "done ticket 2", "ticket_id": "0002"})

    let summary1 = consumeSubmitPrSummary("0001")
    let summary2 = consumeSubmitPrSummary("0002")
    check summary1 == "done ticket 1"
    check summary2 == "done ticket 2"

  test "concurrent start: all open tickets fill available slots in one tick":
    let tmp = getTempDir() / "scriptorium_test_concurrent_start"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    writeSpecInPlan(tmp, "# Spec\n\nConcurrent start test.\n")
    addTicketToPlan(tmp, "open", "0001-alpha.md", "# Ticket Alpha\n\n**Area:** area-a\n")
    addTicketToPlan(tmp, "open", "0002-beta.md", "# Ticket Beta\n\n**Area:** area-b\n")
    addTicketToPlan(tmp, "open", "0003-gamma.md", "# Ticket Gamma\n\n**Area:** area-c\n")

    var cfg = defaultConfig()
    cfg.concurrency.maxAgents = 4
    writeScriptoriumConfig(tmp, cfg)

    var tickCounter = 0
    var tickCounterLock: Lock
    initLock(tickCounterLock)
    var codingStartTicks: Table[string, int] = initTable[string, int]()

    let fakeRunner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      ## Track which tick each coding agent starts on.
      if request.ticketId == "run":
        {.cast(gcsafe).}:
          acquire(tickCounterLock)
          inc tickCounter
          release(tickCounterLock)
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId.startsWith("manager"):
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId.endsWith("-prediction"):
        return AgentRunResult(exitCode: 1, attemptCount: 1, stdout: "")
      elif request.ticketId in ["0001", "0002", "0003"]:
        {.cast(gcsafe).}:
          acquire(tickCounterLock)
          codingStartTicks[request.ticketId] = tickCounter
          release(tickCounterLock)
        recordSubmitPrSummary("done " & request.ticketId, request.ticketId)
        return AgentRunResult(exitCode: 0, attemptCount: 1, lastMessage: "Done.", timeoutKind: "none")
      else:
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "", timeoutKind: "none")

    runOrchestratorForTicks(tmp, 3, fakeRunner)

    acquire(tickCounterLock)
    let finalTicks = codingStartTicks
    release(tickCounterLock)
    deinitLock(tickCounterLock)

    # All 3 tickets must have been started.
    check finalTicks.len == 3
    check "0001" in finalTicks
    check "0002" in finalTicks
    check "0003" in finalTicks

    # All 3 coding agents should start on the same tick (fill available slots).
    var tickValues: seq[int] = @[]
    for ticketId, tick in finalTicks:
      tickValues.add(tick)
    check tickValues.deduplicate().len == 1

  test "managers are prioritized over coding agents when slots are scarce":
    let tmp = getTempDir() / "scriptorium_test_manager_priority"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    writeSpecInPlan(tmp, "# Spec\n\nManager priority test.\n")
    addAreaToPlan(tmp, "area-a.md", "# Area A\n")
    addAreaToPlan(tmp, "area-b.md", "# Area B\n")
    addTicketToPlan(tmp, "open", "0001-task.md", "# Task\n\n**Area:** area-a\n")

    var cfg = defaultConfig()
    cfg.concurrency.maxAgents = 2
    writeScriptoriumConfig(tmp, cfg)

    var callOrder: seq[string] = @[]
    var callOrderLock: Lock
    initLock(callOrderLock)

    let fakeRunner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      ## Track invocation order by ticketId.
      if request.ticketId == "run":
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId.startsWith("manager"):
        {.cast(gcsafe).}:
          acquire(callOrderLock)
          callOrder.add(request.ticketId)
          release(callOrderLock)
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId.endsWith("-prediction"):
        return AgentRunResult(exitCode: 1, attemptCount: 1, stdout: "")
      elif request.ticketId == "0001":
        {.cast(gcsafe).}:
          acquire(callOrderLock)
          callOrder.add(request.ticketId)
          release(callOrderLock)
        recordSubmitPrSummary("done 0001", "0001")
        return AgentRunResult(exitCode: 0, attemptCount: 1, lastMessage: "Done.", timeoutKind: "none")
      else:
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "", timeoutKind: "none")

    runOrchestratorForTicks(tmp, 4, fakeRunner)

    acquire(callOrderLock)
    let finalOrder = callOrder
    release(callOrderLock)
    deinitLock(callOrderLock)

    # Manager for area-b must appear before the coding agent for ticket 0001.
    let managerIdx = finalOrder.find("manager-area-b")
    let coderIdx = finalOrder.find("0001")
    check managerIdx >= 0
    check coderIdx >= 0
    check managerIdx < coderIdx

  test "stall detection works independently per agent":
    let tmp = getTempDir() / "scriptorium_test_concurrent_stall"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-staller.md", "# Ticket Staller\n\n**Area:** area-s\n")
    addTicketToPlan(tmp, "open", "0002-submitter.md", "# Ticket Submitter\n\n**Area:** area-t\n")
    var stallCfg = defaultConfig()
    stallCfg.timeouts.codingAgentMaxAttempts = 2
    writeScriptoriumConfig(tmp, stallCfg)

    let assignment1 = assignOldestOpenTicket(tmp)
    let assignment2 = assignOldestOpenTicket(tmp)
    check assignment1.inProgressTicket.len > 0
    check assignment2.inProgressTicket.len > 0

    ticketStartTimes["0001"] = epochTime()
    ticketStartTimes["0002"] = epochTime()
    ticketAttemptCounts["0001"] = 0
    ticketAttemptCounts["0002"] = 0
    ticketCodingWalls["0001"] = 0.0
    ticketCodingWalls["0002"] = 0.0
    ticketTestWalls["0001"] = 0.0
    ticketTestWalls["0002"] = 0.0
    ticketModels["0001"] = ""
    ticketModels["0002"] = ""
    ticketStdoutBytes["0001"] = 0
    ticketStdoutBytes["0002"] = 0

    var stallCallCount = 0
    proc stallingRunner(request: AgentRunRequest): AgentRunResult =
      ## Stalls on every call: exit 0 without calling submit_pr.
      inc stallCallCount
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        lastMessage: "I stalled.",
        timeoutKind: "none",
      )

    proc submittingRunner(request: AgentRunRequest): AgentRunResult =
      ## Submits immediately on first call.
      recordSubmitPrSummary("submitted", "0002")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        lastMessage: "Done.",
        timeoutKind: "none",
      )

    let result1 = executeAssignedTicket(tmp, assignment1, stallingRunner)
    let result2 = executeAssignedTicket(tmp, assignment2, submittingRunner)

    check stallCallCount == 2
    check result1.submitted == false
    check result2.submitted == true

    let files = planTreeFiles(tmp)
    check "tickets/open/0001-staller.md" in files
    let hasMergeEntry = files.anyIt(it.startsWith("queue/merge/pending/") and it.contains("0002"))
    check hasMergeEntry
