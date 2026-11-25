import
  std/[os, posix, strformat, strutils],
  ./[agent_runner, architect_agent, config, git_ops, lock_management, prompt_builders, shared_state]

const
  PlanSessionTicketId = "plan-session"
  AskSessionTicketId = "ask-session"
  DoSessionTicketId = "do-session"
  AskWriteScopeName = "scriptorium ask"

var
  interactivePlanInterrupted {.volatile.} = false

proc handleInteractivePlanCtrlC() {.noconv.} =
  ## Request shutdown of one interactive planning session on Ctrl+C.
  interactivePlanInterrupted = true

proc inputErrorIndicatesInterrupt(message: string): bool =
  ## Return true when one input error string indicates interrupted input.
  let lower = message.toLowerAscii()
  result = lower.contains("interrupted") or lower.contains("eintr")

type
  ArchitectTurnResult* = object
    agentResult*: AgentRunResult
    response*: string
    specChanged*: bool

proc requireArchitectAnswer(response: var AgentRunResult) =
  ## Reject an otherwise completed conversational turn that produced no answer after tool activity.
  if response.exitCode == 0 and response.failureKind == failureNone and response.lastMessage.strip().len == 0:
    response.exitCode = 1
    response.failureKind = failureProtocol
    response.errorMessage = "Architect ended the turn without an answer."
    if response.failedTools.len > 0:
      response.errorMessage.add(" Failed tools: " & $response.failedTools.len & ".")

proc runArchitectPlanTurn*(
  runner: AgentRunner,
  repoPath: string,
  planPath: string,
  architect: AgentConfig,
  history: seq[PlanTurn],
  line: string,
  turnNum: int,
  ticketId: string,
  onEvent: AgentEventHandler,
): ArchitectTurnResult =
  ## Run one spec-only planning turn and accept an already committed native spec update.
  ## Callers must hold the admin lock and own the plan worktree for the whole turn.
  let
    prevSpec = readFile(planPath / PlanSpecPath)
    previousHead = gitRunCapture(planPath, @["rev-parse", "HEAD"]).output.strip()
  let prompt = buildInteractivePlanPrompt(repoPath, planPath, prevSpec, history, line)
  result.agentResult = runPlanArchitectRequest(runner, repoPath, planPath, architect,
    prompt, ticketId, onEvent, PlanHeartbeatIntervalMs)
  requireArchitectAnswer(result.agentResult)
  try:
    enforceWriteAllowlist(planPath, [PlanSpecPath], PlanWriteScopeName)
    if result.agentResult.exitCode == 0:
      let
        specChanged = readFile(planPath / PlanSpecPath) != prevSpec
        commitMessage = fmt"scriptorium: plan session turn {turnNum}"
      discard withCommitLock(repoPath, proc(): bool =
        ## Validate committed native work and commit only remaining dirty spec bytes.
        if gitCheck(planPath, "merge-base", "--is-ancestor", previousHead, "HEAD") != 0:
          raise newException(ValueError, "Native Plan rewrote history; inspect the preserved plan state")
        let changes = gitRunCapture(planPath, @["log", "--format=", "--name-only", previousHead & "..HEAD"])
        if changes.exitCode != 0:
          raise newException(IOError, "Cannot validate native Plan commits: " & changes.output)
        for path in changes.output.splitLines():
          if path.len > 0 and path != PlanSpecPath:
            raise newException(ValueError, "Native Plan commit changed disallowed path: " & path)
        if specChanged:
          gitRun(planPath, "add", "--", PlanSpecPath)
          if gitCheck(planPath, "diff", "--cached", "--quiet", "--", PlanSpecPath) != 0:
            gitRun(planPath, "commit", "--only", "-m", commitMessage, "--", PlanSpecPath)
        true
      )
      result.response = result.agentResult.lastMessage.strip()
      result.specChanged = specChanged
  except CatchableError as error:
    # Settle known post-turn errors without replaying or rewriting native side effects.
    if result.agentResult.failureKind == failureNone:
      result.agentResult.exitCode = 1
      result.agentResult.failureKind = failureProtocol
    result.agentResult.errorMessage.add(" Plan finalization failed; native work was preserved: " & error.msg)

proc runArchitectAskTurn*(
  runner: AgentRunner,
  repoPath: string,
  planPath: string,
  architect: AgentConfig,
  history: seq[PlanTurn],
  line: string,
  ticketId: string,
  onEvent: AgentEventHandler,
): ArchitectTurnResult =
  ## Run one read-only question turn and revert any plan-worktree writes.
  let spec = readFile(planPath / PlanSpecPath)
  let prompt = buildInteractiveAskPrompt(repoPath, planPath, spec, history, line)
  result.agentResult = runPlanArchitectRequest(runner, repoPath, planPath, architect,
    prompt, ticketId, onEvent, PlanHeartbeatIntervalMs, AskReadOnlyTools)
  enforceNoWrites(planPath, AskWriteScopeName)
  requireArchitectAnswer(result.agentResult)
  if result.agentResult.exitCode == 0:
    result.response = result.agentResult.lastMessage.strip()

proc runInteractivePlanSession*(
  repoPath: string,
  runner: AgentRunner = runAgent,
  input: PlanSessionInput = nil,
  quiet: bool = false,
  resumeSessionId: string = "",
) =
  ## Run a multi-turn interactive planning session with the Architect.
  if runner.isNil:
    raise newException(ValueError, "agent runner is required")

  let conversation = newConversationRunner(runner, resumeSessionId,
    proc(): bool =
      ## Observe Ctrl+C from the owner thread.
      interactivePlanInterrupted)
  defer: conversation.close()

  interactivePlanInterrupted = false
  setControlCHook(handleInteractivePlanCtrlC)
  defer:
    when declared(unsetControlCHook):
      unsetControlCHook()
    interactivePlanInterrupted = false

  let cfg = loadConfig(repoPath)
  acquireAdminLock(repoPath)
  defer: releaseAdminLock(repoPath)
  discard withLockedPlanWorktree(repoPath, proc(planPath: string): int =
    if not quiet:
      echo "scriptorium: interactive planning session (type /help for commands, /quit to exit)"
    var history: seq[PlanTurn] = @[]
    var turnNum = 0

    while true:
      if interactivePlanInterrupted:
        if not quiet:
          echo ""
        break

      if not quiet:
        stdout.write("> ")
        flushFile(stdout)
      var line: string
      try:
        if input.isNil:
          line = readLine(stdin)
        else:
          line = input()
      except EOFError:
        break
      except CatchableError as err:
        if interactivePlanInterrupted or inputErrorIndicatesInterrupt(err.msg):
          if not quiet:
            echo ""
          break
        raise err

      line = line.strip()
      if line.len == 0:
        continue

      case line
      of "/quit", "/exit":
        break
      of "/show":
        let specPath = planPath / PlanSpecPath
        if not quiet:
          if fileExists(specPath):
            echo readFile(specPath)
          else:
            echo "scriptorium: spec.md not found"
        continue
      of "/help":
        if not quiet:
          echo "/show  — print current spec.md"
          echo "/quit  — exit the session"
          echo "/help  — show this list"
        continue
      else:
        if line.startsWith("/"):
          if not quiet:
            echo fmt"scriptorium: unknown command '{line}'"
          continue

      inc turnNum
      var lastStreamLine = "[thinking] working..."
      if not quiet:
        echo lastStreamLine
      let streamEventHandler = proc(event: AgentStreamEvent) =
        ## Render live architect stream events in concise interactive form.
        if quiet:
          return
        let rendered = formatPlanStreamEvent(event)
        if rendered.len > 0 and rendered != lastStreamLine:
          echo rendered
          lastStreamLine = rendered
      let turn = runArchitectPlanTurn(conversation.runner, repoPath, planPath,
        cfg.agents.architect, (if runner == runAgent: @[] else: history), line, turnNum,
        PlanSessionTicketId, streamEventHandler)
      turn.agentResult.requireAgentCompleted()
      if turn.response.len > 0 and not quiet:
        echo turn.response

      history.add(PlanTurn(role: "engineer", text: line))
      history.add(PlanTurn(role: "architect", text: turn.response))

      if turn.specChanged and not quiet:
        echo fmt"[spec.md updated — turn {turnNum}]"
    0
  )

proc runInteractiveAskSession*(
  repoPath: string,
  runner: AgentRunner = runAgent,
  input: PlanSessionInput = nil,
  quiet: bool = false,
  resumeSessionId: string = "",
) =
  ## Run a multi-turn read-only Q&A session with the Architect.
  if runner.isNil:
    raise newException(ValueError, "agent runner is required")

  let conversation = newConversationRunner(runner, resumeSessionId,
    proc(): bool =
      ## Observe Ctrl+C from the owner thread.
      interactivePlanInterrupted)
  defer: conversation.close()

  interactivePlanInterrupted = false
  setControlCHook(handleInteractivePlanCtrlC)
  defer:
    when declared(unsetControlCHook):
      unsetControlCHook()
    interactivePlanInterrupted = false

  let cfg = loadConfig(repoPath)
  acquireAdminLock(repoPath)
  defer: releaseAdminLock(repoPath)
  discard withPlanWorktree(repoPath, proc(planPath: string): int =
    if not quiet:
      echo "scriptorium: ask session (read-only, type /help for commands, /quit to exit)"
    var history: seq[PlanTurn] = @[]

    while true:
      if interactivePlanInterrupted:
        if not quiet:
          echo ""
        break

      if not quiet:
        stdout.write("> ")
        flushFile(stdout)
      var line: string
      try:
        if input.isNil:
          line = readLine(stdin)
        else:
          line = input()
      except EOFError:
        break
      except CatchableError as err:
        if interactivePlanInterrupted or inputErrorIndicatesInterrupt(err.msg):
          if not quiet:
            echo ""
          break
        raise err

      line = line.strip()
      if line.len == 0:
        continue

      case line
      of "/quit", "/exit":
        break
      of "/show":
        let specPath = planPath / PlanSpecPath
        if not quiet:
          if fileExists(specPath):
            echo readFile(specPath)
          else:
            echo "scriptorium: spec.md not found"
        continue
      of "/help":
        if not quiet:
          echo "/show  — print current spec.md"
          echo "/quit  — exit the session"
          echo "/help  — show this list"
        continue
      else:
        if line.startsWith("/"):
          if not quiet:
            echo fmt"scriptorium: unknown command '{line}'"
          continue

      var lastStreamLine = "[thinking] working..."
      if not quiet:
        echo lastStreamLine
      let streamEventHandler = proc(event: AgentStreamEvent) =
        ## Render live architect stream events in concise interactive form.
        if quiet:
          return
        let rendered = formatPlanStreamEvent(event)
        if rendered.len > 0 and rendered != lastStreamLine:
          echo rendered
          lastStreamLine = rendered
      let turn = runArchitectAskTurn(conversation.runner, repoPath, planPath,
        cfg.agents.architect, (if runner == runAgent: @[] else: history), line,
        AskSessionTicketId, streamEventHandler)
      turn.agentResult.requireAgentCompleted()
      if turn.response.len > 0 and not quiet:
        echo turn.response

      history.add(PlanTurn(role: "engineer", text: line))
      history.add(PlanTurn(role: "architect", text: turn.response))
    0
  )

proc runOneShotDoSession*(
  repoPath: string,
  prompt: string,
  runner: AgentRunner = runAgent,
  quiet: bool = false,
) =
  ## Run a single ad-hoc task with the Architect using full repo access.
  if runner.isNil:
    raise newException(ValueError, "agent runner is required")
  acquireAdminLock(repoPath)
  defer: releaseAdminLock(repoPath)
  let cfg = loadConfig(repoPath)
  let builtPrompt = buildDoOneShotPrompt(repoPath, prompt)
  let agentResult = runDoArchitectRequest(
    runner,
    repoPath,
    cfg.agents.architect,
    builtPrompt,
    DoSessionTicketId,
  )
  agentResult.requireAgentCompleted()
  var response = agentResult.lastMessage.strip()
  if response.len > 0 and not quiet:
    echo response

proc runInteractiveDoSession*(
  repoPath: string,
  runner: AgentRunner = runAgent,
  input: PlanSessionInput = nil,
  quiet: bool = false,
  resumeSessionId: string = "",
) =
  ## Run a multi-turn interactive coding session with the Architect using full repo access.
  if runner.isNil:
    raise newException(ValueError, "agent runner is required")

  let conversation = newConversationRunner(runner, resumeSessionId,
    proc(): bool =
      ## Observe Ctrl+C from the owner thread.
      interactivePlanInterrupted)
  defer: conversation.close()

  interactivePlanInterrupted = false
  setControlCHook(handleInteractivePlanCtrlC)
  defer:
    when declared(unsetControlCHook):
      unsetControlCHook()
    interactivePlanInterrupted = false

  acquireAdminLock(repoPath)
  defer: releaseAdminLock(repoPath)
  let cfg = loadConfig(repoPath)
  if not quiet:
    echo "scriptorium: do session (full repo access, type /help for commands, /quit to exit)"
  var history: seq[PlanTurn] = @[]

  while true:
    if interactivePlanInterrupted:
      if not quiet:
        echo ""
      break

    if not quiet:
      stdout.write("> ")
      flushFile(stdout)
    var line: string
    try:
      if input.isNil:
        line = readLine(stdin)
      else:
        line = input()
    except EOFError:
      break
    except CatchableError as err:
      if interactivePlanInterrupted or inputErrorIndicatesInterrupt(err.msg):
        if not quiet:
          echo ""
        break
      raise err

    line = line.strip()
    if line.len == 0:
      continue

    case line
    of "/quit", "/exit":
      break
    of "/help":
      if not quiet:
        echo "/quit  — exit the session"
        echo "/help  — show this list"
      continue
    else:
      if line.startsWith("/"):
        if not quiet:
          echo fmt"scriptorium: unknown command '{line}'"
        continue

    let prompt = buildInteractiveDoPrompt(repoPath, (if runner == runAgent: @[] else: history), line)
    var lastStreamLine = "[thinking] working..."
    if not quiet:
      echo lastStreamLine
    let streamEventHandler = proc(event: AgentStreamEvent) =
      ## Render live architect stream events in concise interactive form.
      if quiet:
        return
      let rendered = formatPlanStreamEvent(event)
      if rendered.len > 0 and rendered != lastStreamLine:
        echo rendered
        lastStreamLine = rendered
    let agentResult = runDoArchitectRequest(
      conversation.runner,
      repoPath,
      cfg.agents.architect,
      prompt,
      DoSessionTicketId,
      streamEventHandler,
      PlanHeartbeatIntervalMs,
    )

    agentResult.requireAgentCompleted()
    var response = agentResult.lastMessage.strip()
    if response.len > 0 and not quiet:
      echo response

    history.add(PlanTurn(role: "engineer", text: line))
    history.add(PlanTurn(role: "architect", text: response))
