import
  std/[algorithm, os, osproc, sequtils, strformat, strutils, tables, times],
  ./[agent_runner, config, git_ops, lock_management, logging, output_formatting, prompt_builders, shared_state, ticket_analysis, ticket_metadata]

const
  MergeQueueInitCommitMessage = "scriptorium: initialize merge queue"
  MergeQueueEnqueueCommitPrefix* = "scriptorium: enqueue merge request"
  MergeQueueDoneCommitPrefix* = "scriptorium: complete ticket"
  MergeQueueReopenCommitPrefix* = "scriptorium: reopen ticket"
  MergeQueueCleanupCommitPrefix = "scriptorium: cleanup merge queue"
  MergeQueueStuckCommitPrefix* = "scriptorium: park stuck ticket"
  MaxMergeFailures = 3
  RequiredQualityTargets* = ["test", "integration-test"]
  QualityCheckTimeoutMs* = 300_000
  MakeTestTimeoutMs* = 300_000
  ReviewAgentNoOutputTimeoutMs = 120_000
  ReviewAgentHardTimeoutMs = 300_000
  ReviewAgentCommitPrefix = "scriptorium: review ticket"

proc runWorktreeMakeTest*(worktreePath: string): tuple[exitCode: int, output: string] =
  ## Run `make test` in the agent worktree and return exit code and combined output.
  result = runCommandCapture(worktreePath, "make", @["test"], MakeTestTimeoutMs)

proc runRequiredQualityChecks*(workingDir: string): tuple[exitCode: int, output: string, failedTarget: string] =
  ## Run required make quality targets in order and stop on first failure.
  var combinedOutput = ""
  var firstFailureExitCode = 0
  var failedTarget = ""

  for target in RequiredQualityTargets:
    let targetResult = runCommandCapture(workingDir, "make", @[target])
    let commandLine = &"$ make {target}"
    let cleanOutput = targetResult.output.strip()
    if combinedOutput.len > 0:
      combinedOutput &= "\n\n"
    if cleanOutput.len > 0:
      combinedOutput &= commandLine & "\n" & cleanOutput
    else:
      combinedOutput &= commandLine

    if targetResult.exitCode != 0 and firstFailureExitCode == 0:
      firstFailureExitCode = targetResult.exitCode
      failedTarget = target
      break

  result = (
    exitCode: firstFailureExitCode,
    output: combinedOutput,
    failedTarget: failedTarget,
  )

proc withMasterWorktree*[T](repoPath: string, operation: proc(masterPath: string): T): T =
  ## Open a deterministic /tmp worktree for master when needed, then remove it.
  if gitCheck(repoPath, "rev-parse", "--verify", "master") != 0:
    raise newException(ValueError, "master branch does not exist")

  let worktreeList = runCommandCapture(repoPath, "git", @["worktree", "list", "--porcelain"])
  if worktreeList.exitCode != 0:
    raise newException(IOError, fmt"git worktree list failed: {worktreeList.output.strip()}")

  var currentPath = ""
  for line in worktreeList.output.splitLines():
    if line.startsWith("worktree "):
      currentPath = line["worktree ".len..^1].strip()
    elif line == "branch refs/heads/master" and currentPath.len > 0:
      return operation(currentPath)

  let masterWorktree = managedMasterWorktreePath(repoPath)
  addWorktreeWithRecovery(repoPath, masterWorktree, "master")
  defer:
    discard gitCheck(repoPath, "worktree", "remove", "--force", masterWorktree)

  result = operation(masterWorktree)

proc queueFilePrefixNumber(fileName: string): int =
  ## Parse the numeric prefix from a merge queue file name.
  let base = splitFile(fileName).name
  let dashPos = base.find('-')
  if dashPos < 1:
    return 0
  let prefix = base[0..<dashPos]
  if not prefix.allCharsInSet(Digits):
    return 0
  result = parseInt(prefix)

proc nextMergeQueueId(planPath: string): int =
  ## Compute the next monotonic merge queue identifier.
  result = 1
  for pendingPath in listMarkdownFiles(planPath / PlanMergeQueuePendingDir):
    let parsed = queueFilePrefixNumber(extractFilename(pendingPath))
    if parsed >= result:
      result = parsed + 1

proc ensureMergeQueueInitializedInPlanPath*(planPath: string): bool =
  ## Ensure merge queue directories and files exist in the plan worktree.
  createDir(planPath / PlanMergeQueuePendingDir)
  let keepPath = planPath / PlanMergeQueuePendingDir / ".gitkeep"
  if not fileExists(keepPath):
    writeFile(keepPath, "")
    result = true

  let activePath = planPath / PlanMergeQueueActivePath
  if not fileExists(activePath):
    writeFile(activePath, "")
    result = true

proc ticketPathInState(planPath: string, stateDir: string, item: MergeQueueItem): string =
  ## Return the expected ticket path for one ticket state directory.
  result = planPath / stateDir / extractFilename(item.ticketPath)

proc clearActiveQueueInPlanPath(planPath: string): bool =
  ## Clear queue/merge/active.md when it contains a pending item path.
  let activePath = planPath / PlanMergeQueueActivePath
  if fileExists(activePath) and readFile(activePath).strip().len > 0:
    writeFile(activePath, "")
    result = true

proc commitMergeQueueCleanup(planPath: string, ticketId: string) =
  ## Commit merge queue cleanup changes when tracked files were modified.
  gitRun(planPath, "add", "-A", PlanMergeQueueDir)
  if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
    let suffix = if ticketId.len > 0: " " & ticketId else: ""
    gitRun(planPath, "commit", "-m", MergeQueueCleanupCommitPrefix & suffix)

proc listMergeQueueItems*(planPath: string): seq[MergeQueueItem] =
  ## Return merge queue items ordered by file name.
  let pendingRoot = planPath / PlanMergeQueuePendingDir
  if not dirExists(pendingRoot):
    return @[]

  var relPaths: seq[string] = @[]
  for absPath in listMarkdownFiles(pendingRoot):
    let fileName = extractFilename(absPath)
    if fileName == ".gitkeep":
      continue
    relPaths.add(relativePath(absPath, planPath).replace('\\', '/'))
  relPaths.sort()

  for relPath in relPaths:
    let content = readFile(planPath / relPath)
    result.add(parseMergeQueueItem(relPath, content))

proc ensureMergeQueueInitialized*(repoPath: string): bool =
  ## Ensure the merge queue structure exists on the plan branch.
  result = withLockedPlanWorktree(repoPath, proc(planPath: string): bool =
    let changed = ensureMergeQueueInitializedInPlanPath(planPath)
    if changed:
      gitRun(planPath, "add", PlanMergeQueueDir)
      if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
        gitRun(planPath, "commit", "-m", MergeQueueInitCommitMessage)
    changed
  )

proc enqueueMergeRequest*(
  repoPath: string,
  assignment: TicketAssignment,
  summary: string,
): string =
  ## Persist a merge request into the plan-branch merge queue.
  if assignment.inProgressTicket.len == 0:
    raise newException(ValueError, "in-progress ticket path is required")
  if assignment.branch.len == 0:
    raise newException(ValueError, "assignment branch is required")
  if assignment.worktree.len == 0:
    raise newException(ValueError, "assignment worktree is required")
  if summary.strip().len == 0:
    raise newException(ValueError, "merge summary is required")

  result = withLockedPlanWorktree(repoPath, proc(planPath: string): string =
    discard ensureMergeQueueInitializedInPlanPath(planPath)

    let queueId = nextMergeQueueId(planPath)
    let ticketId = ticketIdFromTicketPath(assignment.inProgressTicket)
    let pendingRelPath = PlanMergeQueuePendingDir / fmt"{queueId:04d}-{ticketId}.md"
    let item = MergeQueueItem(
      pendingPath: pendingRelPath,
      ticketPath: assignment.inProgressTicket,
      ticketId: ticketId,
      branch: assignment.branch,
      worktree: assignment.worktree,
      summary: summary.strip(),
    )

    writeFile(planPath / pendingRelPath, queueItemToMarkdown(item))
    gitRun(planPath, "add", PlanMergeQueueDir)
    if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
      gitRun(planPath, "commit", "-m", MergeQueueEnqueueCommitPrefix & " " & ticketId)
    logInfo(fmt"ticket {ticketId}: merge queue entered (position={queueId})")
    pendingRelPath
  )

proc runReviewAgent*(
  repoPath: string,
  planPath: string,
  item: MergeQueueItem,
  ticketContent: string,
  submitSummary: string,
  runner: AgentRunner = runAgent,
): tuple[action: string, feedback: string] =
  ## Run the review agent for a merge queue item and return the review decision.
  ## Caller must hold the plan worktree lock and pass planPath.
  let cfg = loadConfig(repoPath)
  let model = cfg.agents.reviewer.model

  let diffResult = runCommandCapture(item.worktree, "git", @["diff", "master..." & item.branch])
  let diffContent = if diffResult.exitCode == 0: diffResult.output else: "(diff unavailable)"

  let areaId = parseAreaFromTicketContent(ticketContent)
  let areaContent = if areaId.len > 0:
    let areaPath = planPath / PlanAreasDir / areaId & ".md"
    if fileExists(areaPath): readFile(areaPath) else: "(area not found)"
  else:
    "(no area specified)"

  let prompt = buildReviewAgentPrompt(ticketContent, diffContent, areaContent, submitSummary)

  discard consumeReviewDecision()

  logInfo(fmt"ticket {item.ticketId}: review started (model={model})")
  let reviewStartTime = epochTime()
  let request = AgentRunRequest(
    prompt: prompt,
    workingDir: item.worktree,
    harness: cfg.agents.reviewer.harness,
    model: cfg.agents.reviewer.model,
    reasoningEffort: cfg.agents.reviewer.reasoningEffort,
    mcpEndpoint: cfg.endpoints.local,
    ticketId: item.ticketId,
    attempt: 1,
    skipGitRepoCheck: true,
    noOutputTimeoutMs: ReviewAgentNoOutputTimeoutMs,
    hardTimeoutMs: ReviewAgentHardTimeoutMs,
    maxAttempts: 1,
    onEvent: proc(event: AgentStreamEvent) =
      if event.kind == agentEventTool:
        logDebug(fmt"review[{item.ticketId}]: {event.text}"),
  )
  let agentResult = runner(request)
  let reviewWallTime = epochTime() - reviewStartTime
  let reviewWallDuration = formatDuration(reviewWallTime)

  result = consumeReviewDecision()

  if result.action == "approve":
    logInfo(fmt"ticket {item.ticketId}: review approved")
  elif result.action == "request_changes":
    let feedbackSummary = truncateTail(result.feedback.strip(), 200)
    logInfo(&"ticket {item.ticketId}: review requested changes (feedback=\"{feedbackSummary}\")")
  else:
    logWarn(fmt"ticket {item.ticketId}: review agent stalled, defaulting to approve")
    result.action = "approve"
    result.feedback = ""

  let ticketPath = planPath / item.ticketPath
  if fileExists(ticketPath):
    let currentContent = readFile(ticketPath)
    let reviewNote = if result.action == "approve":
      "## Review\n" &
        "**Review:** approved\n" &
        fmt"- Model: {model}" & "\n" &
        fmt"- Backend: {agentResult.backend}" & "\n" &
        fmt"- Exit Code: {agentResult.exitCode}" & "\n" &
        fmt"- Wall Time: {reviewWallDuration}" & "\n"
    else:
      "## Review\n" &
        "**Review:** changes requested\n" &
        fmt"- Model: {model}" & "\n" &
        fmt"- Backend: {agentResult.backend}" & "\n" &
        fmt"- Exit Code: {agentResult.exitCode}" & "\n" &
        fmt"- Wall Time: {reviewWallDuration}" & "\n" &
        "\n**Review Feedback:** " & result.feedback.strip() & "\n"
    let updatedContent = currentContent.strip() & "\n\n" & reviewNote
    writeFile(ticketPath, updatedContent)
    gitRun(planPath, "add", item.ticketPath)
    if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
      gitRun(planPath, "commit", "-m", ReviewAgentCommitPrefix & " " & item.ticketId)

proc processMergeQueue*(repoPath: string, runner: AgentRunner = runAgent): bool =
  ## Process at most one merge queue item and apply success/failure transitions.
  result = withLockedPlanWorktree(repoPath, proc(planPath: string): bool =
    discard ensureMergeQueueInitializedInPlanPath(planPath)
    let activePath = planPath / PlanMergeQueueActivePath

    let queueItems = listMergeQueueItems(planPath)
    if queueItems.len == 0:
      if clearActiveQueueInPlanPath(planPath):
        commitMergeQueueCleanup(planPath, "")
        return true
      return false

    let item = queueItems[0]
    writeFile(activePath, item.pendingPath & "\n")
    let queuePath = planPath / item.pendingPath
    let ticketPath = planPath / item.ticketPath
    if not fileExists(ticketPath):
      let doneTicketPath = ticketPathInState(planPath, PlanTicketsDoneDir, item)
      let openTicketPath = ticketPathInState(planPath, PlanTicketsOpenDir, item)
      let hasTerminalTicket = fileExists(doneTicketPath) or fileExists(openTicketPath)
      if hasTerminalTicket:
        if fileExists(queuePath):
          removeFile(queuePath)
        writeFile(activePath, "")
        commitMergeQueueCleanup(planPath, item.ticketId)
        return true
      raise newException(ValueError, fmt"ticket does not exist in plan branch: {item.ticketPath}")

    # Recover missing worktrees (e.g. after container restart wiped /tmp).
    if not dirExists(item.worktree):
      let branchExists = gitCheck(repoPath, "rev-parse", "--verify", item.branch) == 0
      if branchExists:
        logInfo(fmt"processMergeQueue: recovering missing worktree for {item.ticketId} from branch {item.branch}")
        addWorktreeWithRecovery(repoPath, item.worktree, item.branch)
      else:
        logWarn(fmt"processMergeQueue: worktree and branch both missing for {item.ticketId}, reopening ticket")
        let missingStartTime = ticketStartTimes.getOrDefault(item.ticketId, 0.0)
        let missingTotalWall = if missingStartTime > 0.0: formatDuration(epochTime() - missingStartTime) else: "unknown"
        let missingAttempts = ticketAttemptCounts.getOrDefault(item.ticketId, 0)
        logInfo(fmt"ticket {item.ticketId}: in-progress -> open (reopened, reason=worktree and branch missing, attempts={missingAttempts}, total wall={missingTotalWall})")
        sessionStats.ticketsReopened += 1
        let failureNote = "## Merge Queue Failure\n" &
          fmt"- Summary: {item.summary}" & "\n" &
          "- Failed gate: worktree and branch missing (container restart?)\n"
        let metricsNote = formatMetricsNote(item.ticketId, "reopened", "stall").strip()
        let missingWallSeconds = if missingStartTime > 0.0: int(epochTime() - missingStartTime) else: 0
        cleanupTicketTimings(item.ticketId)
        let contentWithNotes = readFile(ticketPath).strip() & "\n\n" & failureNote & "\n\n" & metricsNote & "\n"
        let updatedContent = runPostAnalysis(contentWithNotes, item.ticketId, "reopened", missingAttempts, missingWallSeconds)
        let openRelPath = PlanTicketsOpenDir / extractFilename(item.ticketPath)
        writeFile(ticketPath, updatedContent)
        moveFile(ticketPath, planPath / openRelPath)
        if fileExists(queuePath):
          removeFile(queuePath)
        writeFile(activePath, "")
        gitRun(planPath, "add", "-A", PlanTicketsInProgressDir, PlanTicketsOpenDir, PlanMergeQueueDir)
        if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
          gitRun(planPath, "commit", "-m", MergeQueueReopenCommitPrefix & " " & item.ticketId)
        return true

    let dirtyCheck = runCommandCapture(item.worktree, "git", @["status", "--porcelain"])
    if dirtyCheck.exitCode == 0 and dirtyCheck.output.strip().len > 0:
      logInfo(fmt"processMergeQueue: auto-committing dirty worktree for {item.ticketId}")
      gitRun(item.worktree, "add", "-A")
      gitRun(item.worktree, "commit", "-m", "scriptorium: auto-commit before merge")

    # Run review agent before quality gates.
    let ticketContent = readFile(ticketPath)
    let reviewDecision = runReviewAgent(repoPath, planPath, item, ticketContent, item.summary, runner)
    if reviewDecision.action == "request_changes":
      let attempts = ticketAttemptCounts.getOrDefault(item.ticketId, 0)
      ticketAttemptCounts[item.ticketId] = attempts + 1
      let startTime = ticketStartTimes.getOrDefault(item.ticketId, 0.0)
      let totalWall = if startTime > 0.0: formatDuration(epochTime() - startTime) else: "unknown"
      logInfo(fmt"ticket {item.ticketId}: in-progress -> open (reopened, reason=review changes requested, attempts={attempts + 1}, total wall={totalWall})")
      sessionStats.ticketsReopened += 1
      let openRelPath = PlanTicketsOpenDir / extractFilename(item.ticketPath)
      let currentContent = readFile(ticketPath)
      writeFile(ticketPath, currentContent)
      moveFile(ticketPath, planPath / openRelPath)
      if fileExists(queuePath):
        removeFile(queuePath)
      writeFile(activePath, "")
      gitRun(planPath, "add", "-A", PlanTicketsInProgressDir, PlanTicketsOpenDir, PlanMergeQueueDir)
      if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
        gitRun(planPath, "commit", "-m", MergeQueueReopenCommitPrefix & " " & item.ticketId)
      return true

    logInfo(fmt"ticket {item.ticketId}: merge started (make test running)")
    let mergeStartTime = epochTime()
    let mergeMasterResult = runCommandCapture(item.worktree, "git", @["merge", "--no-edit", "master"])
    var qualityCheckResult = (exitCode: 0, output: "", failedTarget: "")
    if mergeMasterResult.exitCode == 0:
      qualityCheckResult = runRequiredQualityChecks(item.worktree)

    var mergedToMaster = false
    var failureOutput = qualityCheckResult.output
    var failureStep = ""
    if qualityCheckResult.failedTarget.len > 0:
      failureStep = &"make {qualityCheckResult.failedTarget}"

    if mergeMasterResult.exitCode == 0 and qualityCheckResult.exitCode == 0:
      let mergeToMasterResult = withMasterWorktree(repoPath, proc(masterPath: string): tuple[exitCode: int, output: string] =
        let ffResult = runCommandCapture(masterPath, "git", @["merge", "--ff-only", item.branch])
        if ffResult.exitCode == 0:
          return ffResult

        # ff-only failed (master diverged). Try --no-ff with re-verification.
        logInfo(fmt"ticket {item.ticketId}: ff-only failed, attempting --no-ff merge with re-verification")
        let noFfResult = runCommandCapture(masterPath, "git", @["merge", "--no-ff", "--no-edit", item.branch])
        if noFfResult.exitCode != 0:
          discard runCommandCapture(masterPath, "git", @["merge", "--abort"])
          return noFfResult

        # Re-run quality checks on the merged master state
        let recheck = runRequiredQualityChecks(masterPath)
        if recheck.exitCode != 0:
          discard runCommandCapture(masterPath, "git", @["reset", "--hard", "HEAD~1"])
          return (exitCode: recheck.exitCode, output: recheck.output)

        logInfo(fmt"ticket {item.ticketId}: --no-ff merge succeeded with passing quality checks")
        return (exitCode: 0, output: noFfResult.output)
      )
      mergedToMaster = mergeToMasterResult.exitCode == 0
      if not mergedToMaster:
        failureOutput = mergeToMasterResult.output
        failureStep = "git merge master (ff-only and no-ff both failed)"

    if mergeMasterResult.exitCode == 0 and qualityCheckResult.exitCode == 0 and mergedToMaster:
      let mergeWallTime = epochTime() - mergeStartTime
      let mergeWallDuration = formatDuration(mergeWallTime)
      logInfo(fmt"ticket {item.ticketId}: merge succeeded (test wall={mergeWallDuration})")

      let startTime = ticketStartTimes.getOrDefault(item.ticketId, 0.0)
      let totalWall = if startTime > 0.0: formatDuration(epochTime() - startTime) else: "unknown"
      let attempts = ticketAttemptCounts.getOrDefault(item.ticketId, 0)
      logInfo(fmt"ticket {item.ticketId}: in-progress -> done (total wall={totalWall}, attempts={attempts})")
      sessionStats.ticketsCompleted += 1
      sessionStats.mergeQueueProcessed += 1
      if startTime > 0.0:
        sessionStats.completedTicketWalls.add(epochTime() - startTime)
      let codingWall = ticketCodingWalls.getOrDefault(item.ticketId, 0.0)
      sessionStats.completedCodingWalls.add(codingWall)
      let priorTestWall = ticketTestWalls.getOrDefault(item.ticketId, 0.0)
      ticketTestWalls[item.ticketId] = priorTestWall + mergeWallTime
      sessionStats.completedTestWalls.add(priorTestWall + mergeWallTime)
      if attempts <= 1:
        sessionStats.firstAttemptSuccessCount += 1

      let doneRelPath = PlanTicketsDoneDir / extractFilename(item.ticketPath)
      let successNote = formatMergeSuccessNote(item.summary, qualityCheckResult.output).strip()
      let metricsNote = formatMetricsNote(item.ticketId, "done", "").strip()
      let doneWallSeconds = if startTime > 0.0: int(epochTime() - startTime) else: 0
      cleanupTicketTimings(item.ticketId)
      let contentWithNotes = readFile(ticketPath).strip() & "\n\n" & successNote & "\n\n" & metricsNote & "\n"
      let updatedContent = runPostAnalysis(contentWithNotes, item.ticketId, "done", attempts, doneWallSeconds)
      writeFile(ticketPath, updatedContent)
      moveFile(ticketPath, planPath / doneRelPath)
      if fileExists(queuePath):
        removeFile(queuePath)
      writeFile(activePath, "")

      gitRun(planPath, "add", "-A", PlanTicketsInProgressDir, PlanTicketsDoneDir, PlanMergeQueueDir)
      if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
        gitRun(planPath, "commit", "-m", MergeQueueDoneCommitPrefix & " " & item.ticketId)
      true
    else:
      let failureReason = if mergeMasterResult.exitCode != 0: "git merge conflict"
        elif failureStep.len > 0: failureStep
        else: "quality check failed"
      logInfo(fmt"ticket {item.ticketId}: merge failed (reason={failureReason})")

      let failureNote = formatMergeFailureNote(
        item.summary,
        mergeMasterResult.output,
        failureOutput,
        failureStep,
      ).strip()
      let updatedContent = readFile(ticketPath).strip() & "\n\n" & failureNote & "\n"
      let failureCount = updatedContent.count("## Merge Queue Failure")
      let startTime = ticketStartTimes.getOrDefault(item.ticketId, 0.0)
      let totalWall = if startTime > 0.0: formatDuration(epochTime() - startTime) else: "unknown"
      let attempts = ticketAttemptCounts.getOrDefault(item.ticketId, 0)
      if failureCount >= MaxMergeFailures:
        logWarn(fmt"processMergeQueue: parking stuck ticket {item.ticketId} after {failureCount} failures")
        sessionStats.ticketsParked += 1
        let metricsNote = formatMetricsNote(item.ticketId, "parked", "parked").strip()
        let parkedWallSeconds = if startTime > 0.0: int(epochTime() - startTime) else: 0
        cleanupTicketTimings(item.ticketId)
        let stuckRelPath = PlanTicketsStuckDir / extractFilename(item.ticketPath)
        createDir(planPath / PlanTicketsStuckDir)
        let contentWithMetrics = runPostAnalysis(updatedContent.strip() & "\n\n" & metricsNote & "\n", item.ticketId, "parked", attempts, parkedWallSeconds)
        writeFile(ticketPath, contentWithMetrics)
        moveFile(ticketPath, planPath / stuckRelPath)
        if fileExists(queuePath):
          removeFile(queuePath)
        writeFile(activePath, "")
        gitRun(planPath, "add", "-A", PlanTicketsInProgressDir, PlanTicketsStuckDir, PlanMergeQueueDir)
        if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
          gitRun(planPath, "commit", "-m", MergeQueueStuckCommitPrefix & " " & item.ticketId)
      else:
        logInfo(fmt"ticket {item.ticketId}: in-progress -> open (reopened, reason={failureReason}, attempts={attempts}, total wall={totalWall})")
        sessionStats.ticketsReopened += 1
        let metricFailure = if mergeMasterResult.exitCode != 0: "merge_conflict"
          elif failureStep.contains("test"): "test_failure"
          else: "test_failure"
        let metricsNote = formatMetricsNote(item.ticketId, "reopened", metricFailure).strip()
        let reopenWallSeconds = if startTime > 0.0: int(epochTime() - startTime) else: 0
        cleanupTicketTimings(item.ticketId)
        let openRelPath = PlanTicketsOpenDir / extractFilename(item.ticketPath)
        let contentWithMetrics = runPostAnalysis(updatedContent.strip() & "\n\n" & metricsNote & "\n", item.ticketId, "reopened", attempts, reopenWallSeconds)
        writeFile(ticketPath, contentWithMetrics)
        moveFile(ticketPath, planPath / openRelPath)
        if fileExists(queuePath):
          removeFile(queuePath)
        writeFile(activePath, "")
        gitRun(planPath, "add", "-A", PlanTicketsInProgressDir, PlanTicketsOpenDir, PlanMergeQueueDir)
        if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
          gitRun(planPath, "commit", "-m", MergeQueueReopenCommitPrefix & " " & item.ticketId)
      true
  )
