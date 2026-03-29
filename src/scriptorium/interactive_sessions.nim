import
  std/[os, posix, strformat, strutils],
  ./[agent_runner, architect_agent, config, git_ops, lock_management, logging, output_formatting, prompt_builders, shared_state]

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

proc runInteractivePlanSession*(
  repoPath: string,
  runner: AgentRunner = runAgent,
  input: PlanSessionInput = nil,
  quiet: bool = false,
) =
  ## Run a multi-turn interactive planning session with the Architect.
  if runner.isNil:
    raise newException(ValueError, "agent runner is required")

  interactivePlanInterrupted = false
  setControlCHook(handleInteractivePlanCtrlC)
  defer:
    when declared(unsetControlCHook):
      unsetControlCHook()
    interactivePlanInterrupted = false

  let cfg = loadConfig(repoPath)
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

      let prevSpec = readFile(planPath / PlanSpecPath)
      inc turnNum
      let prompt = buildInteractivePlanPrompt(repoPath, planPath, prevSpec, history, line)
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
      let agentResult = runPlanArchitectRequest(
        runner,
        repoPath,
        planPath,
        cfg.agents.architect,
        prompt,
        PlanSessionTicketId,
        streamEventHandler,
        PlanHeartbeatIntervalMs,
      )
      enforceWritePrefixAllowlist(planPath, [PlanSpecPath, PlanTicketsOpenDir], PlanWriteScopeName)

      # Commit any new tickets created by the architect.
      gitRun(planPath, "add", PlanTicketsOpenDir)
      if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
        gitRun(planPath, "commit", "-m", "scriptorium: architect created tickets")

      var response = agentResult.lastMessage.strip()
      if response.len == 0:
        response = agentResult.stdout.strip()
      if response.len > 0 and not quiet:
        echo response

      history.add(PlanTurn(role: "engineer", text: line))
      history.add(PlanTurn(role: "architect", text: response))

      let newSpec = readFile(planPath / PlanSpecPath)
      if newSpec != prevSpec:
        gitRun(planPath, "add", PlanSpecPath)
        gitRun(planPath, "commit", "-m", fmt"scriptorium: plan session turn {turnNum}")
        if not quiet:
          echo fmt"[spec.md updated — turn {turnNum}]"
    0
  )

proc runInteractiveAskSession*(
  repoPath: string,
  runner: AgentRunner = runAgent,
  input: PlanSessionInput = nil,
  quiet: bool = false,
) =
  ## Run a multi-turn read-only Q&A session with the Architect.
  if runner.isNil:
    raise newException(ValueError, "agent runner is required")

  interactivePlanInterrupted = false
  setControlCHook(handleInteractivePlanCtrlC)
  defer:
    when declared(unsetControlCHook):
      unsetControlCHook()
    interactivePlanInterrupted = false

  let cfg = loadConfig(repoPath)
  discard withLockedPlanWorktree(repoPath, proc(planPath: string): int =
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

      let spec = readFile(planPath / PlanSpecPath)
      let prompt = buildInteractiveAskPrompt(repoPath, planPath, spec, history, line)
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
      let agentResult = runPlanArchitectRequest(
        runner,
        repoPath,
        planPath,
        cfg.agents.architect,
        prompt,
        AskSessionTicketId,
        streamEventHandler,
        PlanHeartbeatIntervalMs,
      )
      enforceNoWrites(planPath, AskWriteScopeName)

      var response = agentResult.lastMessage.strip()
      if response.len == 0:
        response = agentResult.stdout.strip()
      if response.len > 0 and not quiet:
        echo response

      history.add(PlanTurn(role: "engineer", text: line))
      history.add(PlanTurn(role: "architect", text: response))
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
  let cfg = loadConfig(repoPath)
  let builtPrompt = buildDoOneShotPrompt(repoPath, prompt)
  let agentResult = runDoArchitectRequest(
    runner,
    repoPath,
    cfg.agents.architect,
    builtPrompt,
    DoSessionTicketId,
  )
  var response = agentResult.lastMessage.strip()
  if response.len == 0:
    response = agentResult.stdout.strip()
  if response.len > 0 and not quiet:
    echo response

proc runInteractiveDoSession*(
  repoPath: string,
  runner: AgentRunner = runAgent,
  input: PlanSessionInput = nil,
  quiet: bool = false,
) =
  ## Run a multi-turn interactive coding session with the Architect using full repo access.
  if runner.isNil:
    raise newException(ValueError, "agent runner is required")

  interactivePlanInterrupted = false
  setControlCHook(handleInteractivePlanCtrlC)
  defer:
    when declared(unsetControlCHook):
      unsetControlCHook()
    interactivePlanInterrupted = false

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

    let prompt = buildInteractiveDoPrompt(repoPath, history, line)
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
      runner,
      repoPath,
      cfg.agents.architect,
      prompt,
      DoSessionTicketId,
      streamEventHandler,
      PlanHeartbeatIntervalMs,
    )

    var response = agentResult.lastMessage.strip()
    if response.len == 0:
      response = agentResult.stdout.strip()
    if response.len > 0 and not quiet:
      echo response

    history.add(PlanTurn(role: "engineer", text: line))
    history.add(PlanTurn(role: "architect", text: response))
