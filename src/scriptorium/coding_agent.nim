import
  std/[locks, os, strformat, strutils, tables, times],
  ./[agent_pool, agent_runner, architect_agent, config, continuation_builder, git_ops, journal, lock_management, log_forwarding, logging, merge_queue, output_formatting, prompt_builders, shared_state, ticket_analysis, ticket_metadata, ticket_assignment]

const
  PredictionNoOutputTimeoutMs = 30_000
  PredictionHardTimeoutMs = 60_000
  PredictionCommitPrefix = "scriptorium: predict ticket"
  TicketAgentRunCommitPrefix = "scriptorium: record agent run"
  TicketAgentFailReopenCommitPrefix = "scriptorium: reopen failed ticket"
  SubmitPrTestOutputMaxChars = 2000
  PartialWorkCommitPrefix* = "scriptorium: save partial agent work (attempt "
  MaxAutoCommitFileBytes* = 1_048_576

export agent_pool

proc gitAddFiltered*(worktreePath: string, maxFileBytes: int = MaxAutoCommitFileBytes) =
  ## Stage all modified and untracked files except those exceeding maxFileBytes.
  ## Logs a warning for each skipped file.
  let result = gitRunCapture(worktreePath, @["ls-files", "--others", "--modified", "--exclude-standard"])
  if result.exitCode != 0 or result.output.strip().len == 0:
    gitRun(worktreePath, "add", "-A")
    return
  var filesToAdd: seq[string] = @[]
  for line in result.output.strip().splitLines():
    let relPath = line.strip()
    if relPath.len == 0:
      continue
    let fullPath = worktreePath / relPath
    if not fileExists(fullPath):
      filesToAdd.add(relPath)
      continue
    let size = getFileSize(fullPath)
    if size > maxFileBytes:
      let sizeMB = size div (1024 * 1024)
      logWarn(&"skipping large file from auto-commit: {relPath} ({sizeMB}MB)")
    else:
      filesToAdd.add(relPath)
  if filesToAdd.len > 0:
    for f in filesToAdd:
      gitRun(worktreePath, "add", f)

proc detectPriorWork*(worktreePath: string, ticketId: string): int =
  ## Detect commits ahead of the default branch on the ticket branch.
  ## Returns the number of prior commits found.
  let defaultBranch = resolveDefaultBranch(worktreePath)
  let logResult = gitRunCapture(worktreePath, @["log", defaultBranch & "..HEAD", "--oneline"])
  if logResult.exitCode != 0:
    return 0
  let lines = logResult.output.strip()
  if lines.len == 0:
    return 0
  result = lines.countLines()
  logInfo(&"ticket {ticketId}: found {result} committed changes from prior attempt, agent will continue from branch tip")

proc validateWorktreeHealth*(repoPath: string, worktreePath: string, branch: string, ticketId: string, attempt: int) =
  ## Validate worktree state before a retry attempt.
  ## Corrupt worktrees are removed and recreated. Dirty worktrees have changes committed.
  let statusResult = gitRunCapture(worktreePath, @["status", "--porcelain"])
  if statusResult.exitCode != 0:
    logInfo(&"ticket {ticketId}: worktree corrupt, recreated from branch")
    discard gitCheck(repoPath, "worktree", "remove", "--force", worktreePath)
    addWorktreeWithRecovery(repoPath, worktreePath, branch)
  elif statusResult.output.strip().len > 0:
    let commitMsg = PartialWorkCommitPrefix & $attempt & ")"
    gitAddFiltered(worktreePath)
    gitRun(worktreePath, "commit", "-m", commitMsg)
    logInfo(&"ticket {ticketId}: saved uncommitted agent work before retry")

proc predictTicketDifficulty*(
  repoPath: string,
  caller: string,
  ticketRelPath: string,
  ticketContent: string,
  runner: AgentRunner = runAgent,
): TicketPrediction =
  ## Run a lightweight prediction prompt to estimate ticket difficulty before assignment.
  ## Returns a TicketPrediction on success. Raises on failure so callers can handle best-effort.
  let cfg = loadConfig(repoPath)
  let ticketId = ticketIdFromTicketPath(ticketRelPath)

  # Gather area content for the ticket.
  let areaId = parseAreaFromTicketContent(ticketContent)
  var areaContent = ""
  if areaId.len > 0:
    areaContent = withPlanWorktree(repoPath, caller, proc(planPath: string): string =
      let areaPath = planPath / PlanAreasDir / areaId & ".md"
      if fileExists(areaPath):
        result = readFile(areaPath)
    )

  # Gather spec summary.
  let specSummary = withPlanWorktree(repoPath, caller, proc(planPath: string): string =
    let specPath = planPath / PlanSpecPath
    if fileExists(specPath):
      let content = readFile(specPath)
      # Use first 2000 chars as summary to keep the prompt short.
      if content.len > 2000:
        result = content[0..<2000] & "\n...(truncated)"
      else:
        result = content
  )

  let prompt = buildPredictionPrompt(ticketContent, areaContent, specSummary)

  let request = AgentRunRequest(
    prompt: prompt,
    workingDir: repoPath,
    harness: cfg.agents.coding.harness,
    model: cfg.agents.coding.model,
    reasoningEffort: cfg.agents.coding.reasoningEffort,
    logRoot: repoPath / ManagedStateDirName / PlanLogDirName / "prediction",
    ticketId: ticketId & "-prediction",
    attempt: 1,
    skipGitRepoCheck: true,
    noOutputTimeoutMs: PredictionNoOutputTimeoutMs,
    hardTimeoutMs: PredictionHardTimeoutMs,
    maxAttempts: 1,
  )

  let agentResult = runner(request)
  if agentResult.exitCode != 0:
    raise newException(ValueError, "prediction agent exited with code " & $agentResult.exitCode)

  let responseText = agentResult.lastMessage.strip()
  if responseText.len == 0:
    raise newException(ValueError, "prediction agent returned empty response")

  result = parsePredictionResponse(responseText)
  logInfo(&"ticket {ticketId}: predicted difficulty={result.difficulty} duration={result.durationMinutes}min")

proc runTicketPrediction*(repoPath: string, caller: string, ticketRelPath: string, runner: AgentRunner = runAgent) =
  ## Run a best-effort prediction for a ticket and persist results to the plan branch.
  let ticketId = ticketIdFromTicketPath(ticketRelPath)
  let ticketContent = withPlanWorktree(repoPath, caller, proc(planPath: string): string =
    readFile(planPath / ticketRelPath)
  )
  try:
    let prediction = predictTicketDifficulty(repoPath, caller, ticketRelPath, ticketContent, runner)
    discard withLockedPlanWorktree(repoPath, caller, proc(planPath: string): int =
      let ticketPath = planPath / ticketRelPath
      if not fileExists(ticketPath):
        return 0
      let currentContent = readFile(ticketPath)
      let updatedContent = appendPredictionNote(currentContent, prediction)
      writeFile(ticketPath, updatedContent)
      gitRun(planPath, "add", ticketRelPath)
      if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
        gitRun(planPath, "commit", "-m", PredictionCommitPrefix & " " & ticketId)
      0
    )
  except CatchableError as e:
    logWarn(&"ticket {ticketId}: prediction failed: {e.msg}")

proc executeAssignedTicket*(
  repoPath: string,
  caller: string,
  assignment: TicketAssignment,
  runner: AgentRunner = runAgent,
  agentConfigOverride: AgentConfig = AgentConfig(),
): AgentRunResult =
  ## Run the coding agent for an assigned in-progress ticket and persist run notes.
  ## When agentConfigOverride has a non-empty model, it overrides the coding agent config.
  if runner.isNil:
    raise newException(ValueError, "agent runner is required")
  if assignment.inProgressTicket.len == 0:
    raise newException(ValueError, "in-progress ticket path is required")
  if assignment.worktree.len == 0:
    raise newException(ValueError, "assignment worktree path is required")

  logDebug(fmt"executeAssignedTicket: loadConfig")
  let cfg = loadConfig(repoPath)
  let ticketRelPath = assignment.inProgressTicket

  logDebug(fmt"executeAssignedTicket: reading ticket from plan worktree")
  let ticketContent = withPlanWorktree(repoPath, caller, proc(planPath: string): string =
    let ticketPath = planPath / ticketRelPath
    if not fileExists(ticketPath):
      raise newException(ValueError, fmt"ticket does not exist in plan branch: {ticketRelPath}")
    readFile(ticketPath)
  )

  logDebug(fmt"executeAssignedTicket: buildCodingAgentPrompt")
  let ticketId = ticketIdFromTicketPath(ticketRelPath)
  let priorCommitCount = detectPriorWork(assignment.worktree, ticketId)
  var priorWorkNote = ""
  if priorCommitCount > 0:
    priorWorkNote = "## Prior Work Detected\n\nThis branch has " & $priorCommitCount &
      " commit(s) from a prior attempt. Review existing changes with `git log` and `git diff` against the default branch before proceeding. Build on the existing work rather than starting over."
  let initialPrompt = buildCodingAgentPrompt(repoPath, assignment.worktree, ticketRelPath, ticketContent, priorWorkNote)

  var currentPrompt = initialPrompt
  var currentAttemptBase = DefaultAgentAttempt
  var totalAttemptsUsed = 0
  var submitSummary = ""
  let agentCfg = if agentConfigOverride.model.len > 0: agentConfigOverride else: cfg.agents.coding
  let model = agentCfg.model
  let maxAttempts = cfg.timeouts.codingAgentMaxAttempts

  setActiveTicketWorktree(assignment.worktree, ticketId)
  defer: clearActiveTicketWorktree(ticketId)

  while totalAttemptsUsed < maxAttempts:
    if totalAttemptsUsed > 0:
      validateWorktreeHealth(repoPath, assignment.worktree, assignment.branch, ticketId, currentAttemptBase)
    let attemptsForThisCall = maxAttempts - totalAttemptsUsed
    logInfo(fmt"ticket {ticketId}: coding agent started (model={model}, attempt {currentAttemptBase}/{maxAttempts})")
    let agentStartTime = epochTime()
    let request = AgentRunRequest(
      prompt: currentPrompt,
      workingDir: assignment.worktree,
      harness: agentCfg.harness,
      model: agentCfg.model,
      reasoningEffort: agentCfg.reasoningEffort,
      mcpEndpoint: cfg.endpoints.local,
      ticketId: ticketId,
      attempt: currentAttemptBase,
      logRoot: repoPath / ManagedStateDirName / PlanLogDirName / "coder",
      skipGitRepoCheck: true,
      noOutputTimeoutMs: agentCfg.noOutputTimeout,
      hardTimeoutMs: agentCfg.hardTimeout,
      progressTimeoutMs: agentCfg.progressTimeout,
      maxAttempts: attemptsForThisCall,
      continuationPromptBuilder: buildAgentsReinjectPrompt,
      onEvent: proc(event: AgentStreamEvent) =
        forwardAgentEvent("coding", ticketId, event),
    )
    discard consumeSubmitPrSummary(ticketId)

    logDebug(fmt"executeAssignedTicket: running coding agent (attempt {currentAttemptBase}/{maxAttempts})")
    let agentResult = runner(request)
    result = agentResult
    totalAttemptsUsed += max(agentResult.attemptCount, 1)

    let agentWallTime = epochTime() - agentStartTime
    let agentWallDuration = formatDuration(agentWallTime)
    let isProgressStall = agentResult.timeoutKind == "progress"
    let isStall = (agentResult.exitCode == 0 and agentResult.timeoutKind == "none") or isProgressStall
    if isProgressStall:
      logInfo(fmt"ticket {ticketId}: agent stalled — output active but no tool calls for progress timeout window")
    logInfo(fmt"ticket {ticketId}: coding agent finished (exit={agentResult.exitCode}, wall={agentWallDuration}, stall={isStall})")

    ensureTimingsLockInitialized()
    acquire(timingsLock)
    if ticketCodingWalls.hasKey(ticketId):
      ticketCodingWalls[ticketId] = ticketCodingWalls[ticketId] + agentWallTime
    else:
      ticketCodingWalls[ticketId] = agentWallTime

    if ticketAttemptCounts.hasKey(ticketId):
      ticketAttemptCounts[ticketId] = ticketAttemptCounts[ticketId] + agentResult.attemptCount
    else:
      ticketAttemptCounts[ticketId] = agentResult.attemptCount

    ticketModels[ticketId] = model
    if ticketStdoutBytes.hasKey(ticketId):
      ticketStdoutBytes[ticketId] = ticketStdoutBytes[ticketId] + agentResult.stdout.len
    else:
      ticketStdoutBytes[ticketId] = agentResult.stdout.len
    release(timingsLock)

    let stdoutTail = truncateTail(agentResult.stdout.strip(), 500)
    let messageTail = truncateTail(agentResult.lastMessage.strip(), 500)
    logDebug(fmt"executeAssignedTicket: agent finished exit={agentResult.exitCode} timeout={agentResult.timeoutKind}")
    if stdoutTail.len > 0:
      logDebug(fmt"executeAssignedTicket: stdout tail: {stdoutTail}")
    if messageTail.len > 0:
      logDebug(fmt"executeAssignedTicket: lastMessage tail: {messageTail}")

    logDebug(fmt"executeAssignedTicket: writing agent run notes to plan worktree")
    discard withLockedPlanWorktree(repoPath, caller, proc(planPath: string): int =
      let ticketPath = planPath / ticketRelPath
      if not fileExists(ticketPath):
        raise newException(ValueError, fmt"ticket does not exist in plan branch: {ticketRelPath}")

      let currentContent = readFile(ticketPath)
      let updatedContent = appendAgentRunNote(currentContent, cfg.agents.coding.model, agentResult)
      writeFile(ticketPath, updatedContent)
      gitRun(planPath, "add", ticketRelPath)
      if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
        let ticketName = splitFile(ticketRelPath).name
        gitRun(planPath, "commit", "-m", TicketAgentRunCommitPrefix & " " & ticketName)
      0
    )

    submitSummary = consumeSubmitPrSummary(ticketId)
    if submitSummary.len > 0:
      break

    if isStall and totalAttemptsUsed < maxAttempts:
      logInfo(fmt"ticket {ticketId}: coding agent stalled (attempt {agentResult.attempt}/{maxAttempts}, no submit_pr)")
      let testStartTime = epochTime()
      let testResult = runWorktreeMakeTest(assignment.worktree)
      let testWallTime = epochTime() - testStartTime
      let testWallDuration = formatDuration(testWallTime)
      let testStatus = if testResult.exitCode == 0: "PASS" else: "FAIL"
      logInfo(fmt"ticket {ticketId}: make test before retry: {testStatus} (exit={testResult.exitCode}, wall={testWallDuration})")

      acquire(timingsLock)
      if ticketTestWalls.hasKey(ticketId):
        ticketTestWalls[ticketId] = ticketTestWalls[ticketId] + testWallTime
      else:
        ticketTestWalls[ticketId] = testWallTime
      release(timingsLock)

      currentAttemptBase = agentResult.attempt + agentResult.attemptCount
      let testStatusLabel = if testResult.exitCode == 0: "passing" else: "failing"
      logInfo(fmt"ticket {ticketId}: continuation prompt sent (attempt {currentAttemptBase}/{maxAttempts}, test_status={testStatusLabel})")
      currentPrompt = buildStallContinuationPrompt(initialPrompt, ticketContent, ticketId, currentAttemptBase, testResult.exitCode, testResult.output)
      continue

    break

  if submitSummary.len > 0:
    result.submitted = true
    logInfo(fmt"ticket {ticketId}: submit_pr called (summary=""{submitSummary}"")")
    let dirtyCheck = gitRunCapture(assignment.worktree, @["status", "--porcelain"])
    if dirtyCheck.exitCode == 0 and dirtyCheck.output.strip().len > 0:
      logInfo(fmt"executeAssignedTicket: auto-committing uncommitted changes")
      gitAddFiltered(assignment.worktree)
      gitRun(assignment.worktree, "commit", "-m", "scriptorium: auto-commit agent changes")
    logDebug(fmt"executeAssignedTicket: enqueueing merge request")
    discard enqueueMergeRequest(repoPath, caller, assignment, submitSummary)
  else:
    let attempts = ticketAttemptCounts.getOrDefault(ticketId, totalAttemptsUsed)
    let startTime = ticketStartTimes.getOrDefault(ticketId, 0.0)
    let totalWall = if startTime > 0.0: formatDuration(epochTime() - startTime) else: "unknown"
    logInfo(fmt"ticket {ticketId}: in-progress -> open (reopened, reason=no submit_pr, attempts={attempts}, total wall={totalWall})")
    sessionStats.ticketsReopened += 1
    let failureReason = case result.timeoutKind
      of "hard": "timeout_hard"
      of "no-output": "timeout_no_output"
      of "progress": "timeout_progress"
      else: "stall"
    let metricsNote = formatMetricsNote(ticketId, "reopened", failureReason).strip()
    let stallWallSeconds = if startTime > 0.0: int(epochTime() - startTime) else: 0
    cleanupTicketTimings(ticketId)
    discard withLockedPlanWorktree(repoPath, caller, proc(planPath: string): int =
      let ticketPath = planPath / ticketRelPath
      let openRelPath = PlanTicketsOpenDir / extractFilename(ticketRelPath)
      if fileExists(ticketPath):
        let currentContent = readFile(ticketPath)
        let contentWithMetrics = runPostAnalysis(currentContent.strip() & "\n\n" & metricsNote & "\n", ticketId, "reopened", attempts, stallWallSeconds)
        let commitMsg = TicketAgentFailReopenCommitPrefix & " " & ticketId
        let steps = @[
          newWriteStep(ticketRelPath, contentWithMetrics),
          newMoveStep(ticketRelPath, openRelPath),
        ]
        beginJournalTransition(planPath, "reopen " & ticketId, steps, commitMsg)
        executeJournalSteps(planPath)
        completeJournalTransition(planPath)
      0
    )

proc executeOldestOpenTicket*(repoPath: string, caller: string, runner: AgentRunner = runAgent): AgentRunResult =
  ## Assign the oldest open ticket and execute it with the coding agent.
  let assignment = assignOldestOpenTicket(repoPath, caller)
  if assignment.inProgressTicket.len == 0:
    logDebug("no open tickets to execute")
    result = AgentRunResult()
  else:
    let ticketId = ticketIdFromTicketPath(assignment.inProgressTicket)
    runTicketPrediction(repoPath, caller, assignment.inProgressTicket, runner)
    result = executeAssignedTicket(repoPath, caller, assignment, runner)
    result.ticketId = ticketId

proc codingAgentWorkerThread*(args: AgentThreadArgs) {.thread.} =
  ## Run executeAssignedTicket in a background thread and send the result to the pool channel.
  {.cast(gcsafe).}:
    let runner: AgentRunner = if not agentRunnerOverride.isNil: agentRunnerOverride else: runAgent
    let agentResult = executeAssignedTicket(args.repoPath, PlanCallerOrchestrator, args.assignment, runner)
    sendPoolResult(AgentPoolCompletionResult(
      role: arCoder,
      ticketId: args.ticketId,
      result: agentResult,
    ))
