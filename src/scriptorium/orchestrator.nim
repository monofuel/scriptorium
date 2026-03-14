import
  std/[os, posix, strformat, strutils, tables, times],
  mcport,
  ./[agent_runner, architect_agent, coding_agent, config, git_ops, health_checks, interactive_sessions, lock_management, logging, manager_agent, mcp_server, merge_queue, output_formatting, prompt_builders, shared_state, ticket_analysis, ticket_assignment, ticket_metadata]

export shared_state, git_ops, lock_management, ticket_metadata, prompt_builders, output_formatting, ticket_analysis, health_checks,
  architect_agent, manager_agent, merge_queue, ticket_assignment, coding_agent, mcp_server, interactive_sessions

const
  IdleSleepMs = 200
  IdleBackoffSleepMs = 30_000
  WaitingNoSpecMessage = "WAITING: no spec — run 'scriptorium plan'"

proc handlePosixSignal(signalNumber: cint) {.noconv.} =
  ## Stop the orchestrator loop on SIGINT/SIGTERM.
  logInfo(fmt"shutdown: signal {signalNumber} received")
  shouldRun = false

proc installSignalHandlers() =
  ## Install signal handlers used by the orchestrator run loop.
  posix.signal(SIGINT, handlePosixSignal)
  posix.signal(SIGTERM, handlePosixSignal)

proc checkMasterHealth(repoPath: string): tuple[healthy: bool, testExitCode: int, integrationTestExitCode: int, testWallSeconds: int, integrationTestWallSeconds: int] =
  ## Run the master health check and return detailed results.
  let checkResult = withMasterWorktree(repoPath, proc(masterPath: string): tuple[testExitCode: int, integrationTestExitCode: int, testWallSeconds: int, integrationTestWallSeconds: int] =
    var testExitCode = 0
    var integrationTestExitCode = 0
    var testWall = 0
    var integrationTestWall = 0
    for target in RequiredQualityTargets:
      let t0 = epochTime()
      let targetResult = runCommandCapture(masterPath, "make", @[target])
      let elapsed = int(epochTime() - t0)
      if target == "test":
        testExitCode = targetResult.exitCode
        testWall = elapsed
      elif target == "integration-test":
        integrationTestExitCode = targetResult.exitCode
        integrationTestWall = elapsed
      if targetResult.exitCode != 0:
        break
    result = (testExitCode: testExitCode, integrationTestExitCode: integrationTestExitCode, testWallSeconds: testWall, integrationTestWallSeconds: integrationTestWall)
  )
  let healthy = checkResult.testExitCode == 0 and checkResult.integrationTestExitCode == 0
  result = (healthy: healthy, testExitCode: checkResult.testExitCode, integrationTestExitCode: checkResult.integrationTestExitCode, testWallSeconds: checkResult.testWallSeconds, integrationTestWallSeconds: checkResult.integrationTestWallSeconds)

proc isMasterHealthy(repoPath: string, state: var MasterHealthState): bool =
  ## Return cached master health, refreshing only when the master commit changes.
  ## Checks in-memory cache first, then file cache on plan branch, then runs checks.
  let currentHead = masterHeadCommit(repoPath)
  if state.initialized and state.head == currentHead:
    return state.healthy

  # In-memory miss — check file cache on plan branch.
  if hasPlanBranch(repoPath):
    let cachedEntry = withPlanWorktree(repoPath, proc(planPath: string): tuple[found: bool, entry: HealthCacheEntry] =
      let cache = readHealthCache(planPath)
      if currentHead in cache:
        result = (found: true, entry: cache[currentHead])
      else:
        result = (found: false, entry: HealthCacheEntry())
    )
    if cachedEntry.found:
      state.head = currentHead
      state.healthy = cachedEntry.entry.healthy
      state.initialized = true
      if cachedEntry.entry.healthy:
        logInfo(&"master health: cached healthy for {currentHead}")
      else:
        logInfo(&"master health: cached unhealthy for {currentHead}")
      return state.healthy

  # Cache miss — run health checks.
  let healthResult = checkMasterHealth(repoPath)
  state.head = currentHead
  state.healthy = healthResult.healthy
  state.initialized = true

  # Persist to file cache on plan branch.
  if hasPlanBranch(repoPath):
    let nowStr = now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    let newEntry = HealthCacheEntry(
      healthy: healthResult.healthy,
      timestamp: nowStr,
      test_exit_code: healthResult.testExitCode,
      integration_test_exit_code: healthResult.integrationTestExitCode,
      test_wall_seconds: healthResult.testWallSeconds,
      integration_test_wall_seconds: healthResult.integrationTestWallSeconds,
    )
    discard withLockedPlanWorktree(repoPath, proc(planPath: string): bool =
      var cache = readHealthCache(planPath)
      cache[currentHead] = newEntry
      writeHealthCache(planPath, cache)
      commitHealthCache(planPath)
      result = true
    )

  result = state.healthy

proc logSessionSummary*() =
  ## Log two INFO lines summarizing session-wide statistics on shutdown.
  let uptime = formatDuration(epochTime() - sessionStats.startTime)
  let countsLine = &"session summary: uptime={uptime} ticks={sessionStats.totalTicks} tickets_completed={sessionStats.ticketsCompleted} tickets_reopened={sessionStats.ticketsReopened} tickets_parked={sessionStats.ticketsParked} merge_queue_processed={sessionStats.mergeQueueProcessed}"
  logInfo(countsLine)

  var avgTicketWall = "n/a"
  var avgCodingWall = "n/a"
  var avgTestWall = "n/a"
  var firstAttemptSuccess = "0"

  if sessionStats.ticketsCompleted > 0:
    var totalTicketWall = 0.0
    for w in sessionStats.completedTicketWalls:
      totalTicketWall += w
    avgTicketWall = formatDuration(totalTicketWall / sessionStats.ticketsCompleted.float)

    var totalCodingWall = 0.0
    for w in sessionStats.completedCodingWalls:
      totalCodingWall += w
    avgCodingWall = formatDuration(totalCodingWall / sessionStats.ticketsCompleted.float)

    var totalTestWall = 0.0
    for w in sessionStats.completedTestWalls:
      totalTestWall += w
    avgTestWall = formatDuration(totalTestWall / sessionStats.ticketsCompleted.float)

    let pct = (sessionStats.firstAttemptSuccessCount * 100) div sessionStats.ticketsCompleted
    firstAttemptSuccess = $pct & "%"

  let averagesLine = &"session summary: avg_ticket_wall={avgTicketWall} avg_coding_wall={avgCodingWall} avg_test_wall={avgTestWall} first_attempt_success={firstAttemptSuccess}"
  logInfo(averagesLine)

proc runOrchestratorMainLoop(repoPath: string, maxTicks: int, runner: AgentRunner) =
  ## Execute the orchestrator polling loop for an optional bounded number of ticks.
  agentRunnerOverride = runner
  sessionStats.startTime = epochTime()
  ensureTimingsLockInitialized()
  let cfg = loadConfig(repoPath)
  let maxAgents = cfg.concurrency.maxAgents
  var ticks = 0
  var idle = false
  var masterHealthState = MasterHealthState()
  while shouldRun:
    if maxTicks >= 0 and ticks >= maxTicks:
      break
    try:
      idle = false
      logDebug(fmt"tick {ticks}")

      # Check for completed agents at the start of every tick (parallel mode).
      if maxAgents > 1:
        let completions = checkCompletedAgents()
        for completion in completions:
          let running = runningAgentCount()
          logInfo(&"agent slots: {running}/{maxAgents} (ticket {completion.ticketId} finished)")
          if isRateLimited(completion.result.stdout) or isRateLimited(completion.result.lastMessage):
            recordRateLimit(completion.ticketId)

      # Restore concurrency when backoff expires.
      discard isRateLimitBackoffActive()

      if not hasPlanBranch(repoPath):
        logDebug("waiting: no plan branch")
        idle = true
      else:
        logDebug(fmt"tick {ticks}: checking master health")
        var t0 = epochTime()
        let healthy = isMasterHealthy(repoPath, masterHealthState)
        logDebug(fmt"tick {ticks}: master health check took {epochTime() - t0:.1f}s, healthy={healthy}")
        if not healthy and not masterHealthState.lastHealthLogged:
          logWarn("master is unhealthy — skipping tick")
          masterHealthState.lastHealthLogged = true
        elif healthy and masterHealthState.lastHealthLogged:
          logInfo(fmt"master is healthy again (commit {masterHealthState.head})")
          masterHealthState.lastHealthLogged = false

        if not healthy:
          idle = true
        elif not shouldRun:
          discard
        else:
          var architectStatus = "skipped"
          var managerStatus = "skipped"
          var codingStatus = "idle"
          var mergeStatus = "idle"
          var codingDidWork = false

          if hasRunnableSpec(repoPath):
            logInfo("architect: generating areas from spec")
            t0 = epochTime()
            let architectChanged = runArchitectAreas(repoPath, runner)
            logDebug(fmt"tick {ticks}: architect took {epochTime() - t0:.1f}s, changed={architectChanged}")
            if architectChanged:
              logInfo("architect: areas updated")
              architectStatus = "updated"
            else:
              architectStatus = "no-op"

            if not shouldRun: break

            logInfo("manager: generating tickets")
            t0 = epochTime()
            let managerChanged = runManagerTickets(repoPath, runner)
            logDebug(fmt"tick {ticks}: manager took {epochTime() - t0:.1f}s, changed={managerChanged}")
            if managerChanged:
              logInfo("manager: tickets created")
              managerStatus = "updated"
            else:
              managerStatus = "no-op"

            if not shouldRun: break

            let tokenBudgetMB = cfg.concurrency.tokenBudgetMB
            if isTokenBudgetExceeded(tokenBudgetMB):
              codingStatus = "budget-exceeded"
            elif isRateLimitBackoffActive():
              codingStatus = "rate-limited"
            elif maxAgents <= 1:
              # Serial mode: blocking execution of one ticket per tick.
              t0 = epochTime()
              let agentResult = executeOldestOpenTicket(repoPath, runner)
              let codingWallTime = epochTime() - t0
              logDebug(fmt"tick {ticks}: coding agent took {codingWallTime:.1f}s, exit={agentResult.exitCode}")

              if agentResult.command.len > 0:
                codingDidWork = true
                let codingDuration = formatDuration(codingWallTime)
                if agentResult.timeoutKind != "none":
                  codingStatus = fmt"{agentResult.ticketId}(stalled, {codingDuration})"
                elif agentResult.submitted:
                  codingStatus = fmt"{agentResult.ticketId}(submitted, {codingDuration})"
                else:
                  codingStatus = fmt"{agentResult.ticketId}(failed, {codingDuration})"
            else:
              # Parallel mode: assign tickets to empty slots and start non-blocking.
              let effectiveMax = effectiveMaxAgents(maxAgents)
              let slotsAvailable = emptySlotCount(effectiveMax)
              if slotsAvailable > 0:
                let assignments = assignOpenTickets(repoPath, slotsAvailable)
                for assignment in assignments:
                  let ticketId = ticketIdFromTicketPath(assignment.inProgressTicket)
                  runTicketPrediction(repoPath, assignment.inProgressTicket, runner)
                  startAgentAsync(repoPath, assignment, maxAgents)
                  codingDidWork = true
                let running = runningAgentCount()
                codingStatus = &"{running}/{maxAgents} agents"

            if not shouldRun: break

            logInfo("merge queue: processing")
            t0 = epochTime()
            let mergeProcessed = processMergeQueue(repoPath)
            logDebug(fmt"tick {ticks}: merge queue took {epochTime() - t0:.1f}s, processed={mergeProcessed}")
            if mergeProcessed:
              logInfo("merge queue: item processed")
              mergeStatus = "processing"

            if maxAgents <= 1:
              if not architectChanged and not managerChanged and not codingDidWork and not mergeProcessed:
                logDebug(fmt"tick {ticks}: idle")
                idle = true
            else:
              if not architectChanged and not managerChanged and not codingDidWork and not mergeProcessed and runningAgentCount() == 0:
                logDebug(fmt"tick {ticks}: idle")
                idle = true
          else:
            logDebug(WaitingNoSpecMessage)
            idle = true

          let ticketCounts = readOrchestratorStatus(repoPath)
          let summary = fmt"tick {ticks} summary: architect={architectStatus} manager={managerStatus} coding={codingStatus} merge={mergeStatus} open={ticketCounts.openTickets} in-progress={ticketCounts.inProgressTickets} done={ticketCounts.doneTickets}"
          logInfo(summary)
    except CatchableError as e:
      logError(fmt"tick {ticks} failed: {e.msg}")
      idle = true  # backoff on persistent errors to prevent spin-loop
    if idle:
      sleep(IdleBackoffSleepMs)
    else:
      sleep(IdleSleepMs)
    inc ticks
  # On shutdown, wait for running agents to complete.
  if maxAgents > 1 and runningAgentCount() > 0:
    logInfo(&"shutdown: waiting for {runningAgentCount()} running agent(s)")
    joinAllAgentThreads()
  sessionStats.totalTicks = ticks
  logSessionSummary()

proc runOrchestratorLoop(
  repoPath: string,
  httpServer: HttpMcpServer,
  endpoint: OrchestratorEndpoint,
  maxTicks: int,
  runner: AgentRunner,
) =
  ## Start HTTP transport and execute the orchestrator idle event loop.
  shouldRun = true
  installSignalHandlers()

  var serverThread: Thread[ServerThreadArgs]
  createThread(serverThread, runHttpServer, (httpServer, endpoint.address, endpoint.port))
  waitForServerReady(endpoint.address, endpoint.port)
  runOrchestratorMainLoop(repoPath, maxTicks, runner)

  shouldRun = false
  signalServerShutdown()
  logDebug("waiting for HTTP server thread to exit")
  joinThread(serverThread)
  logDebug("HTTP server thread exited")

proc runOrchestratorForTicks*(repoPath: string, maxTicks: int, runner: AgentRunner = runAgent) =
  ## Run a bounded orchestrator loop without starting the MCP HTTP server.
  shouldRun = true
  runOrchestratorMainLoop(repoPath, maxTicks, runner)
  shouldRun = false

proc parseLogLevel(value: string): LogLevel =
  ## Parse a log level string into a LogLevel enum value.
  case value.toLowerAscii()
  of "debug": lvlDebug
  of "info": lvlInfo
  of "warn", "warning": lvlWarn
  of "error": lvlError
  else:
    raise newException(ValueError, fmt"unknown log level: {value}")

proc applyLogLevelFromConfig(repoPath: string) =
  ## Apply log level from config or environment variable.
  let cfg = loadConfig(repoPath)
  if cfg.logLevel.len > 0:
    try:
      setLogLevel(parseLogLevel(cfg.logLevel))
    except ValueError:
      logWarn(fmt"unknown log level '{cfg.logLevel}', using default")
  if cfg.fileLogLevel.len > 0:
    try:
      setFileLogLevel(parseLogLevel(cfg.fileLogLevel))
    except ValueError:
      logWarn(fmt"unknown file log level '{cfg.fileLogLevel}', using default")

proc runOrchestrator*(repoPath: string) =
  ## Start the orchestrator daemon with HTTP MCP and an idle event loop.
  initLog(repoPath)
  applyLogLevelFromConfig(repoPath)
  let endpoint = loadOrchestratorEndpoint(repoPath)
  logInfo(fmt"orchestrator listening on http://{endpoint.address}:{endpoint.port}")
  logInfo(fmt"repo: {repoPath}")
  logInfo(fmt"build: {BuildCommitHash}")
  logInfo(fmt"log file: {logFilePath}")
  let httpServer = createOrchestratorServer()
  defer: closeLog()
  runOrchestratorLoop(repoPath, httpServer, endpoint, -1, runAgent)
