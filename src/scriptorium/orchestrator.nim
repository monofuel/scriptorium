import
  std/[os, osproc, posix, strformat, strutils, tables, times],
  mcport,
  ./[agent_pool, agent_runner, architect_agent, coding_agent, config, cycle_detection, git_ops, health_checks, init, interactive_sessions, lock_management, logging, loop_system, manager_agent, mcp_server, merge_queue, notifications, output_formatting, pause_flag, prompt_builders, recovery, remote_sync, shared_state, stuck_investigation, ticket_analysis, ticket_assignment, ticket_metadata]

export shared_state, git_ops, lock_management, ticket_metadata, prompt_builders, output_formatting, ticket_analysis, health_checks,
  agent_pool, architect_agent, manager_agent, merge_queue, ticket_assignment, coding_agent, mcp_server, interactive_sessions, cycle_detection, recovery, loop_system, pause_flag, stuck_investigation

const
  IdleSleepMs = 200
  AgentPollSleepMs = 10_000
  IdleBackoffSleepMs = 30_000
  WaitingNoSpecMessage = "WAITING: no spec — run 'scriptorium plan'"
  UnstickCommitPrefix = "scriptorium: unstick ticket"

var tickSleepOverrideMs*: int = -1
  ## When >= 0, overrides both idle and active sleep durations in the tick loop.
  ## Set to 0 in tests to eliminate wall-clock sleep.

proc handlePosixSignal(signalNumber: cint) {.noconv.} =
  ## Stop the orchestrator loop on SIGINT/SIGTERM.
  logInfo(&"shutdown: signal {signalNumber} received")
  shouldRun = false

proc installSignalHandlers() =
  ## Install signal handlers used by the orchestrator run loop.
  posix.signal(SIGINT, handlePosixSignal)
  posix.signal(SIGTERM, handlePosixSignal)

proc checkMasterHealth(repoPath: string): tuple[healthy: bool, testExitCode: int, integrationTestExitCode: int, testWallSeconds: int, integrationTestWallSeconds: int, testOutput: string] =
  ## Run the master health check and return detailed results.
  let checkResult = withMasterWorktree(repoPath, proc(masterPath: string): tuple[testExitCode: int, integrationTestExitCode: int, testWallSeconds: int, integrationTestWallSeconds: int, testOutput: string] =
    var testExitCode = 0
    var integrationTestExitCode = 0
    var testWall = 0
    var integrationTestWall = 0
    var failureOutput = ""
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
        failureOutput = targetResult.output
        break
    result = (testExitCode: testExitCode, integrationTestExitCode: integrationTestExitCode, testWallSeconds: testWall, integrationTestWallSeconds: integrationTestWall, testOutput: failureOutput)
  )
  let healthy = checkResult.testExitCode == 0 and checkResult.integrationTestExitCode == 0
  result = (healthy: healthy, testExitCode: checkResult.testExitCode, integrationTestExitCode: checkResult.integrationTestExitCode, testWallSeconds: checkResult.testWallSeconds, integrationTestWallSeconds: checkResult.integrationTestWallSeconds, testOutput: checkResult.testOutput)

proc isMasterHealthy(repoPath: string, state: var MasterHealthState): bool =
  ## Return cached master health, refreshing only when the master commit changes.
  ## Checks in-memory cache first, then file cache on plan branch, then runs checks.
  let branchName = resolveDefaultBranch(repoPath)
  let currentHead = defaultBranchHeadCommit(repoPath)
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
        logInfo(&"{branchName} health: cached healthy for {currentHead}")
      else:
        logInfo(&"{branchName} health: cached unhealthy for {currentHead}")
      return state.healthy

  # Cache miss — run health checks.
  let healthResult = checkMasterHealth(repoPath)
  state.head = currentHead
  state.healthy = healthResult.healthy
  state.testOutput = healthResult.testOutput
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
    logDebug(&"health cache: writing entry for {currentHead} (healthy={healthResult.healthy})")
    try:
      discard withLockedPlanWorktree(repoPath, proc(planPath: string): bool =
        var cache = readHealthCache(planPath)
        cache[currentHead] = newEntry
        cache = pruneHealthCache(cache, MaxHealthCacheEntries)
        writeHealthCache(planPath, cache)
        commitHealthCache(planPath)
        result = true
      )
    except CatchableError as e:
      logWarn(&"health cache: failed to write entry for {currentHead}: {e.msg}")

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
  ## Execute the orchestrator polling loop with interleaved manager/coder execution.
  ## Tick order: poll completions → backoff/health → architect → managers → coders → merge → sleep.
  discard recoverFromCrash(repoPath)
  agentRunnerOverride = runner
  sessionStats.startTime = epochTime()
  ensureTimingsLockInitialized()
  let cfg = loadConfig(repoPath)
  let maxAgents = cfg.concurrency.maxAgents
  let loopCfg = cfg.loop
  var ticks = 0
  var idle = false
  var loopIterationCount = 0
  var masterHealthState = MasterHealthState()
  var specWaitingLogged = false
  var recoveryAttemptedForCommit = ""
  var queueDrainNotified = false
  let syncCfg = cfg.remoteSync
  var lastSyncTime = 0.0
  while shouldRun:
    if maxTicks >= 0 and ticks >= maxTicks:
      break
    try:
      idle = false
      logDebug(&"tick {ticks}")

      # Step 0: Remote sync — fetch from remotes and merge from primary.
      if syncCfg.enabled:
        let syncElapsed = epochTime() - lastSyncTime
        if syncCfg.syncIntervalSeconds <= 0 or syncElapsed >= syncCfg.syncIntervalSeconds.float:
          try:
            let syncResult = syncRemotes(repoPath, syncCfg)
            lastSyncTime = epochTime()
            if syncResult.mergeResult != smrUpToDate:
              logInfo(&"remote sync: merge={syncResult.mergeResult} fetched={syncResult.fetchedRemotes} pushed={syncResult.pushedRemotes}")
            else:
              logDebug("remote sync: up to date")
          except CatchableError as e:
            logWarn(&"remote sync failed: {e.msg}")

      # Step 1: Poll completed agents (managers + coders).
      let completions = checkCompletedAgents()
      for completion in completions:
        let running = runningAgentCount()
        if completion.role == arManager:
          let areaId = completion.areaId
          let ticketDocs = completion.managerResult
          logInfo(&"agent slots: {running}/{maxAgents} (manager {areaId} finished, {ticketDocs.len} tickets)")
          discard withLockedPlanWorktree(repoPath, proc(planPath: string): bool =
            if ticketDocs.len > 0:
              let nextId = nextTicketId(planPath)
              writeTicketsForAreaFromStrings(planPath, areaId, ticketDocs, nextId)
              gitRun(planPath, "add", PlanTicketsOpenDir)
              if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
                gitRun(planPath, "commit", "-m", "scriptorium: create tickets for " & areaId)
            # Always update area hashes so this area is not re-ticketed next tick.
            let currentHashes = computeAllAreaHashes(planPath)
            writeAreaHashes(planPath, currentHashes)
            gitRun(planPath, "add", AreaHashesPath)
            if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
              gitRun(planPath, "commit", "-m", AreaHashesCommitMessage)
            true
          )
        else:
          logInfo(&"agent slots: {running}/{maxAgents} (ticket {completion.ticketId} finished)")

      # Pause check: skip new assignments but continue merge queue and completions.
      if isPaused(repoPath):
        logInfo("orchestrator paused, skipping new assignments")
        let mergeProcessed = processMergeQueue(repoPath)
        if mergeProcessed:
          logInfo("merge queue: item processed (paused)")
          let cleaned = cleanupStaleTicketWorktrees(repoPath)
          for path in cleaned:
            logInfo(&"worktree cleaned after merge: {path}")
        idle = true
      elif not hasPlanBranch(repoPath):
        logDebug("waiting: no plan branch")
        idle = true
      else:
        let defaultBranch = resolveDefaultBranch(repoPath)
        logDebug(&"tick {ticks}: checking {defaultBranch} health")
        var t0 = epochTime()
        let healthy = isMasterHealthy(repoPath, masterHealthState)
        let healthElapsed = epochTime() - t0
        logDebug(&"tick {ticks}: {defaultBranch} health check took {healthElapsed:.1f}s, healthy={healthy}")
        if not healthy and not masterHealthState.lastHealthLogged:
          logWarn(&"{defaultBranch} is unhealthy — skipping tick")
          masterHealthState.lastHealthLogged = true
        elif healthy and masterHealthState.lastHealthLogged:
          logInfo(&"{defaultBranch} is healthy again (commit {masterHealthState.head})")
          masterHealthState.lastHealthLogged = false

        var architectStatus = "skipped"
        var managerStatus = "skipped"
        var codingStatus = "idle"
        var mergeStatus = "idle"
        var codingDidWork = false
        var architectChanged = false
        var managerChanged = false

        # When healthy, run the normal pipeline: architect → managers → coders.
        # When unhealthy, skip new ticket work but allow merge queue + recovery below.
        if not healthy:
          idle = true
        elif not shouldRun:
          discard
        elif hasRunnableSpec(repoPath):
          specWaitingLogged = false
          # Step 3: Run architect (sequential, must complete before managers).
          logDebug("architect: generating areas from spec")
          t0 = epochTime()
          architectChanged = runArchitectAreas(repoPath, runner)
          let architectElapsed = epochTime() - t0
          logDebug(&"tick {ticks}: architect took {architectElapsed:.1f}s, changed={architectChanged}")
          if architectChanged:
            logInfo("architect: areas updated")
            architectStatus = "updated"
          else:
            architectStatus = "no-op"

          if not shouldRun: break

          # Step 4+5: Read areas needing tickets and start managers.
          # Managers are prioritized over coders: they run first to fill slots.
          logDebug("manager: generating tickets")
          t0 = epochTime()
          if maxAgents <= 1:
            managerChanged = runManagerForAreas(repoPath, runner)
          else:
            discard withPlanWorktree(repoPath, proc(planPath: string): int =
              if not hasRunnableSpecInPlanPath(planPath): return 0
              let areasToProcess = areasNeedingTicketsInPlanPath(planPath)
              for areaRelPath in areasToProcess:
                if emptySlotCount(maxAgents) <= 0: break
                let areaId = areaIdFromAreaPath(areaRelPath)
                if isManagerRunningForArea(areaId): continue
                let areaContent = readFile(planPath / areaRelPath)
                let nextId = nextTicketId(planPath)
                startManagerAgentAsync(repoPath, areaId, areaContent, planPath, nextId, maxAgents, managerAgentWorkerThread)
              0
            )
          let managerElapsed = epochTime() - t0
          logDebug(&"tick {ticks}: manager took {managerElapsed:.1f}s, changed={managerChanged}")
          if managerChanged:
            logInfo("manager: tickets created")
            managerStatus = "updated"
            discard withPlanWorktree(repoPath, proc(planPath: string): int =
              discard detectAndLogCycles(planPath)
              0
            )
          else:
            managerStatus = "no-op"

          if not shouldRun: break

          # Step 6: Start coding agents (use remaining slots after managers).
          let tokenBudgetMB = cfg.concurrency.tokenBudgetMB
          if isTokenBudgetExceeded(tokenBudgetMB):
            codingStatus = "budget-exceeded"
          elif maxAgents <= 1:
            t0 = epochTime()
            let agentResult = executeOldestOpenTicket(repoPath, runner)
            let codingWallTime = epochTime() - t0
            logDebug(&"tick {ticks}: coding agent took {codingWallTime:.1f}s, exit={agentResult.exitCode}")

            if agentResult.command.len > 0:
              codingDidWork = true
              let codingDuration = formatDuration(codingWallTime)
              if agentResult.timeoutKind != "none":
                codingStatus = &"{agentResult.ticketId}(stalled, {codingDuration})"
              elif agentResult.submitted:
                codingStatus = &"{agentResult.ticketId}(submitted, {codingDuration})"
              else:
                codingStatus = &"{agentResult.ticketId}(failed, {codingDuration})"
          else:
            let slotsAvailable = emptySlotCount(maxAgents)
            if slotsAvailable > 0:
              let assignments = assignOpenTickets(repoPath, slotsAvailable)
              for assignment in assignments:
                let ticketId = ticketIdFromTicketPath(assignment.inProgressTicket)
                runTicketPrediction(repoPath, assignment.inProgressTicket, runner)
                startCodingAgentAsync(repoPath, assignment, maxAgents, codingAgentWorkerThread)
                codingDidWork = true
              let running = runningAgentCount()
              codingStatus = &"{running}/{maxAgents} agents"

          if not shouldRun: break
        else:
          if not specWaitingLogged:
            logInfo(WaitingNoSpecMessage)
            specWaitingLogged = true
          else:
            logDebug(WaitingNoSpecMessage)
          idle = true

        # --- Steps below run regardless of health state ---

        if not shouldRun: break

        # Step 7: Process at most one merge-queue item.
        logDebug("merge queue: processing")
        t0 = epochTime()
        let mergeProcessed = processMergeQueue(repoPath)
        let mergeElapsed = epochTime() - t0
        logDebug(&"tick {ticks}: merge queue took {mergeElapsed:.1f}s, processed={mergeProcessed}")
        if mergeProcessed:
          logInfo("merge queue: item processed")
          mergeStatus = "processing"
          let cleaned = cleanupStaleTicketWorktrees(repoPath)
          for path in cleaned:
            logInfo(&"worktree cleaned after merge: {path}")
          # Push merged changes to all remotes immediately.
          if syncCfg.enabled:
            try:
              pushToAllRemotes(repoPath, syncCfg)
            except CatchableError as e:
              logWarn(&"remote push after merge failed: {e.msg}")

        if not architectChanged and not managerChanged and not codingDidWork and not mergeProcessed:
          logDebug(&"tick {ticks}: idle")
          idle = true

        discard withPlanWorktree(repoPath, proc(planPath: string): int =
          scanForCycleBlockedTickets(planPath)
          0
        )

        # Step 7b: Investigate and recover stuck tickets.
        let recoveredCount = investigateAndRecoverStuckTickets(repoPath, runner)
        if recoveredCount > 0:
          logInfo(&"recovered {recoveredCount} stuck ticket(s)")

        # Step 7c: Recovery agent for unhealthy main branch.
        if not healthy and masterHealthState.head != recoveryAttemptedForCommit:
          recoveryAttemptedForCommit = masterHealthState.head
          logInfo(&"recovery: starting recovery agent for unhealthy commit {masterHealthState.head}")
          runRecoveryAgent(repoPath, runner, masterHealthState.testOutput, masterHealthState.head)

        # Step 8: Loop system — feedback cycle when queue is drained or force eval is pending.
        if loopCfg.enabled and loopCfg.feedback.len > 0:
          let drained = withPlanWorktree(repoPath, proc(planPath: string): bool =
            isQueueDrained(planPath)
          )
          let forceEval = forceEvalPending
          if forceEval:
            forceEvalPending = false
            logInfo("loop: force eval triggered by completed ticket")
          if drained and runningAgentCount() == 0 and not queueDrainNotified:
            queueDrainNotified = true
            postNotification(repoPath, "queue-drained", "All tickets complete. Queue is empty.")
          if not drained:
            queueDrainNotified = false
          if (drained and runningAgentCount() == 0) or forceEval:
            if loopCfg.maxIterations > 0 and loopIterationCount >= loopCfg.maxIterations:
              let maxIter = loopCfg.maxIterations
              logInfo(&"loop: max iterations reached ({loopIterationCount}/{maxIter})")
            else:
              inc loopIterationCount
              let cycleT0 = epochTime()
              logInfo(&"loop: queue drained, starting feedback cycle (iteration {loopIterationCount})")
              logInfo(&"loop: running feedback command...")
              let feedbackT0 = epochTime()
              let feedbackResult = runFeedbackCommand(repoPath, loopCfg.feedback, loopCfg.feedbackTimeoutMs)
              let feedbackElapsed = epochTime() - feedbackT0
              if feedbackResult.timedOut:
                logWarn(&"loop: feedback command timed out ({feedbackElapsed:.1f}s)")
              elif feedbackResult.exitCode != 0:
                let exitCode = feedbackResult.exitCode
                logWarn(&"loop: feedback command exited with code {exitCode} ({feedbackElapsed:.1f}s)")
              else:
                logInfo(&"loop: feedback command completed (exit 0, {feedbackElapsed:.1f}s)")
              let feedbackOutput = formatFeedbackResult(feedbackResult)
              try:
                let specUpdated = runArchitectLoopIteration(repoPath, runner, feedbackOutput)
                let cycleElapsed = epochTime() - cycleT0
                if specUpdated:
                  logInfo(&"loop: feedback cycle {loopIterationCount} complete, spec updated (total {cycleElapsed:.1f}s)")
                else:
                  logWarn(&"loop: feedback cycle {loopIterationCount} failed to produce spec changes (total {cycleElapsed:.1f}s)")
              except CatchableError as e:
                let errMsg = e.msg
                let cycleElapsed = epochTime() - cycleT0
                logWarn(&"loop: architect iteration failed ({cycleElapsed:.1f}s): {errMsg}")
              idle = false

        let ticketCounts = readOrchestratorStatus(repoPath)
        let running = runningAgentCount()
        let agentDesc = runningAgentSummary()
        let stuck = ticketCounts.stuckTickets
        let summary = &"tick {ticks} summary: architect={architectStatus} manager={managerStatus} coding={codingStatus} merge={mergeStatus} agents={running}/{maxAgents}({agentDesc}) open={ticketCounts.openTickets} in-progress={ticketCounts.inProgressTickets} done={ticketCounts.doneTickets} stuck={stuck} loop={loopIterationCount}"
        logInfo(summary)
    except CatchableError as e:
      logError(&"tick {ticks} failed: {e.msg}")
      idle = true  # backoff on persistent errors to prevent spin-loop
    if tickSleepOverrideMs >= 0:
      sleep(tickSleepOverrideMs)
    elif idle and runningAgentCount() > 0:
      sleep(AgentPollSleepMs)
    elif idle:
      sleep(IdleBackoffSleepMs)
    else:
      sleep(IdleSleepMs)
    inc ticks
  # On shutdown, wait for running agents to complete.
  if runningAgentCount() > 0:
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
  acquireOrchestratorPidGuard(repoPath)
  defer:
    teardownPlanWorktree(repoPath)
    releaseOrchestratorPidGuard(repoPath)
  shouldRun = true
  runOrchestratorMainLoop(repoPath, maxTicks, runner)
  shouldRun = false

proc harnessBinaryName(h: Harness): string =
  ## Return the expected binary name for a harness.
  case h
  of harnessClaudeCode: "claude"
  of harnessCodex: "codex"
  of harnessTypoi: "typoi"

proc preflightValidation*(repoPath: string) =
  ## Validate that the repo is ready for the orchestrator to run.
  ## Exits with a clear error message if any required precondition is missing.
  var errors: seq[string]

  # 1. scriptorium/plan branch exists.
  if not hasPlanBranch(repoPath):
    errors.add("scriptorium/plan branch is missing. Run `scriptorium init` first.")

  # 2. AGENTS.md exists in repo root.
  if not fileExists(repoPath / "AGENTS.md"):
    errors.add("AGENTS.md is missing from the repo root. Run `scriptorium init` first.")

  # 3. Makefile exists in repo root.
  let makefilePath = repoPath / "Makefile"
  if not fileExists(makefilePath):
    errors.add("Makefile is missing from the repo root. Run `scriptorium init` first.")
  else:
    # 4. Required make targets exist (at minimum `test`).
    let makefileContent = readFile(makefilePath)
    if not makefileContent.contains("test:"):
      errors.add("Makefile is missing a `test:` target. Add a `test` target to your Makefile.")

  # 5. Agent binary is available.
  let cfg = loadConfig(repoPath)
  let binaryName = harnessBinaryName(cfg.agents.coding.harness)
  if findExe(binaryName).len == 0:
    errors.add("Agent binary `" & binaryName & "` not found in PATH. Install it or update scriptorium.json.")

  # 6. nimby is available.
  if findExe("nimby").len == 0:
    errors.add("`nimby` not found in PATH. Install nimby for dependency management.")

  # 7. nim is available and version >= 2.
  let nimPath = findExe("nim")
  if nimPath.len == 0:
    errors.add("`nim` not found in PATH. Install Nim >= 2.0.")
  else:
    let (nimVerOut, nimVerRc) = execCmdEx(nimPath & " --version")
    if nimVerRc != 0:
      errors.add("Failed to determine Nim version.")
    else:
      let firstLine = nimVerOut.strip().splitLines()[0]
      let versionStart = firstLine.find("Version ")
      if versionStart >= 0:
        let versionStr = firstLine[versionStart + 8 .. ^1].strip()
        let majorStr = versionStr.split('.')[0]
        try:
          let major = parseInt(majorStr)
          if major < 2:
            errors.add("Nim version " & versionStr & " is too old. Nim >= 2.0 is required.")
        except ValueError:
          errors.add("Could not parse Nim version from: " & firstLine)
      else:
        errors.add("Could not parse Nim version from: " & firstLine)

  # 8. Agent auth is configured (warning only).
  var hasAuth = false
  case cfg.agents.coding.harness
  of harnessClaudeCode:
    hasAuth = getEnv("ANTHROPIC_API_KEY").len > 0 or
              dirExists(getHomeDir() / ".claude") or
              getEnv("CLAUDE_CODE_USE_BEDROCK").len > 0
  of harnessCodex:
    hasAuth = getEnv("OPENAI_API_KEY").len > 0 or
              getEnv("CODEX_API_KEY").len > 0 or
              dirExists(getHomeDir() / ".codex")
  of harnessTypoi:
    hasAuth = getEnv("ANTHROPIC_API_KEY").len > 0 or
              getEnv("OPENAI_API_KEY").len > 0

  if not hasAuth:
    stderr.writeLine("WARNING: No API credentials detected for " & binaryName & ". Set the appropriate API key environment variable.")

  if errors.len > 0:
    for err in errors:
      stderr.writeLine("ERROR: " & err)
    quit(1)

proc runOrchestrator*(repoPath: string) =
  ## Start the orchestrator daemon with HTTP MCP and an idle event loop.
  preflightValidation(repoPath)
  acquireOrchestratorPidGuard(repoPath)
  defer:
    teardownPlanWorktree(repoPath)
    releaseOrchestratorPidGuard(repoPath)
  normalizeConfig(repoPath)
  let cfg = loadConfig(repoPath)
  if cfg.syncAgentsMd:
    syncAgentsMd(repoPath)
  ensureScriptoriumIgnored(repoPath)
  initLog(repoPath)
  applyLogLevelFromConfig(repoPath)
  let endpoint = loadOrchestratorEndpoint(repoPath)
  logInfo(&"orchestrator listening on http://{endpoint.address}:{endpoint.port}")
  logInfo(&"repo: {repoPath}")
  logInfo(&"build: {BuildCommitHash}")
  logInfo(&"log file: {logFilePath}")
  let httpServer = createOrchestratorServer()
  defer: closeLog()
  runOrchestratorLoop(repoPath, httpServer, endpoint, -1, runAgent)
