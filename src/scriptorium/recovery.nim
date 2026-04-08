## Startup recovery sequence that runs before the first orchestrator tick.
## Also contains the recovery agent for fixing unhealthy main branches.

import
  std/[os, osproc, posix, sets, strformat, strutils, times],
  ./[agent_runner, coding_agent, config, git_ops, journal, lock_management, logging, manager_agent, merge_queue, output_formatting, prompt_builders, shared_state, ticket_assignment, ticket_metadata]

const
  RecoveryCommitMessage = "scriptorium: recovery commit (unclean shutdown)"
  RecoveryMergedCommitPrefix = "scriptorium: recovery — completed already-merged ticket"
  RecoveryTicketCommitPrefix = "scriptorium: create recovery ticket"
  MaxRecoveryTestOutputChars* = 8000

type
  RecoverySummary* = object
    worktreesCleaned*: int
    staleMarkersCleared*: int
    planAction*: string
    alreadyMergedCompleted*: int
    orphanedReopened*: int

proc isScriptoriumProcess(pid: int): bool =
  ## Check if a PID corresponds to a known scriptorium process.
  let cmdlinePath = "/proc/" & $pid & "/cmdline"
  if not fileExists(cmdlinePath):
    return false
  let cmdline = readFile(cmdlinePath)
  result = "scriptorium" in cmdline

proc cleanOrphanedWorktrees*(repoPath: string, caller: string): int =
  ## Step 1: Clean orphaned worktrees and remove locks held by dead PIDs.
  if not hasPlanBranch(repoPath):
    return 0

  let cleaned = cleanupStaleTicketWorktrees(repoPath, caller)
  for path in cleaned:
    logInfo(&"recovery: cleaned orphaned worktree {path}")
  result = cleaned.len

  # Remove git worktree locks held by dead PIDs.
  let worktreeGitDir = repoPath / ".git" / "worktrees"
  if dirExists(worktreeGitDir):
    for kind, path in walkDir(worktreeGitDir):
      if kind != pcDir:
        continue
      let lockFile = path / "locked"
      if not fileExists(lockFile):
        continue
      let lockContent = readFile(lockFile).strip()
      # Try to extract PID from lock content.
      var lockPid = 0
      for word in lockContent.splitWhitespace():
        if word.allCharsInSet(Digits) and word.len > 0:
          lockPid = parseInt(word)
          break
      if lockPid <= 0:
        continue
      let killRc = posix.kill(Pid(lockPid), 0)
      if killRc != 0 and int(osLastError()) == ESRCH:
        removeFile(lockFile)
        logInfo(&"recovery: cleaned orphaned worktree {path} (dead lock PID {lockPid})")
        inc result
      elif killRc == 0 and not isScriptoriumProcess(lockPid):
        logWarn(&"recovery: worktree lock held by unknown process PID {lockPid} in {path}, skipping")

proc detectStaleAgentProcesses*(repoPath: string): int =
  ## Step 2: Detect stale agent processes in worktree directories.
  let managedRoot = managedWorktreeRootPath(repoPath)
  let ticketRoot = managedTicketWorktreeRootPath(repoPath)
  if not dirExists(ticketRoot):
    return 0

  for kind, worktreePath in walkDir(ticketRoot):
    if kind != pcDir:
      continue
    # Check for PID marker files.
    for fileKind, filePath in walkDir(worktreePath):
      if fileKind != pcFile:
        continue
      let fileName = extractFilename(filePath)
      if not (fileName.endsWith(".pid") or fileName.endsWith(".lock")):
        continue
      let content = readFile(filePath).strip()
      var markerPid = 0
      for word in content.splitWhitespace():
        if word.allCharsInSet(Digits) and word.len > 0:
          markerPid = parseInt(word)
          break
      if markerPid <= 0:
        continue
      let killRc = posix.kill(Pid(markerPid), 0)
      if killRc != 0 and int(osLastError()) == ESRCH:
        removeFile(filePath)
        logInfo(&"recovery: cleared stale agent marker for PID {markerPid}")
        inc result
      elif killRc == 0:
        logWarn(&"recovery: stale agent process {markerPid} still running in {worktreePath}, manual intervention may be needed")

proc reconcileDirtyPlanBranch*(repoPath: string, caller: string): string =
  ## Step 3: Reconcile dirty plan branch.
  if not hasPlanBranch(repoPath):
    return "clean"

  result = withLockedPlanWorktree(repoPath, caller, proc(planPath: string): string =
    # Check for journal first.
    if journalExists(planPath):
      logInfo("recovery: journal file found, replaying or rolling back")
      replayOrRollbackJournal(planPath)
      # Determine what happened by checking the last commit.
      let (logOut, logRc) = execCmdEx("git -C " & planPath & " log -1 --format=%s")
      let lastSubject = logOut.strip()
      if "complete transition" in lastSubject:
        let (logOut2, _) = execCmdEx("git -C " & planPath & " log -2 --format=%s")
        let lines = logOut2.strip().splitLines()
        if lines.len >= 2:
          let prevSubject = lines[1].strip()
          if "begin transition" in prevSubject:
            result = "journal-rolled-back"
          else:
            result = "journal-replayed"
        else:
          result = "journal-replayed"
      else:
        result = "journal-replayed"
      logInfo(&"recovery: plan branch reconciled ({result})")
      return

    # Check for uncommitted changes.
    let statusResult = runCommandCapture(planPath, "git", @["status", "--porcelain"])
    if statusResult.exitCode == 0 and statusResult.output.strip().len > 0:
      gitRun(planPath, "add", "-A")
      gitRun(planPath, "commit", "-m", RecoveryCommitMessage)
      result = "committed"
      logInfo(&"recovery: plan branch reconciled ({result})")
      return

    result = "clean"
  )

proc completeAlreadyMergedTickets*(repoPath: string, caller: string): int =
  ## Step 4: Complete in-progress tickets whose branches are already merged into master.
  ## Scans both merge queue items and bare in-progress tickets.
  if not hasPlanBranch(repoPath):
    return 0

  result = withLockedPlanWorktree(repoPath, caller, proc(planPath: string): int =
    let defaultBranch = resolveDefaultBranch(repoPath)
    var completed = 0

    # Clean stale active merge queue marker pointing to nonexistent pending file.
    let activePath = planPath / PlanMergeQueueActivePath
    if fileExists(activePath):
      let activeContent = readFile(activePath).strip()
      if activeContent.len > 0:
        let referencedPath = planPath / activeContent
        if not fileExists(referencedPath):
          logInfo(&"recovery: clearing stale active marker referencing missing {activeContent}")
          writeFile(activePath, "")
          gitRun(planPath, "add", PlanMergeQueueActivePath)
          if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
            gitRun(planPath, "commit", "-m", "scriptorium: recovery — clear stale active marker")

    # Complete merge queue items whose branches are already merged.
    discard ensureMergeQueueInitializedInPlanPath(planPath)
    let items = listMergeQueueItems(planPath)
    for item in items:
      let checkResult = runCommandCapture(
        repoPath, "git", @["merge-base", "--is-ancestor", item.branch, defaultBranch],
      )
      if checkResult.exitCode != 0:
        continue

      let ticketPath = planPath / item.ticketPath
      if not fileExists(ticketPath):
        continue

      let doneRelPath = PlanTicketsDoneDir / extractFilename(item.ticketPath)
      createDir(planPath / PlanTicketsDoneDir)
      logDebug(&"recovery: moving queued ticket {item.ticketId} to done (already merged)")
      moveFile(ticketPath, planPath / doneRelPath)

      let queuePath = planPath / item.pendingPath
      if fileExists(queuePath):
        removeFile(queuePath)

      if fileExists(activePath):
        let activeContent = readFile(activePath).strip()
        if activeContent == item.pendingPath:
          writeFile(activePath, "")

      gitRun(planPath, "add", "-A", PlanTicketsInProgressDir, PlanTicketsDoneDir, PlanMergeQueueDir)
      if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
        let commitMsg = RecoveryMergedCommitPrefix & " " & item.ticketId
        gitRun(planPath, "commit", "-m", commitMsg)

      logInfo(&"recovery: completed already-merged ticket {item.ticketId}")
      inc completed

    # Complete bare in-progress tickets whose branches are already merged.
    let inProgressDir = planPath / PlanTicketsInProgressDir
    if dirExists(inProgressDir):
      for ticketPath in listMarkdownFiles(inProgressDir):
        let fileName = extractFilename(ticketPath)
        let ticketId = ticketIdFromTicketPath(fileName)
        let branch = TicketBranchPrefix & ticketId
        let branchExists = gitCheck(repoPath, "rev-parse", "--verify", branch)
        if branchExists != 0:
          continue
        let checkResult = runCommandCapture(
          repoPath, "git", @["merge-base", "--is-ancestor", branch, defaultBranch],
        )
        if checkResult.exitCode != 0:
          continue

        let doneRelPath = PlanTicketsDoneDir / fileName
        createDir(planPath / PlanTicketsDoneDir)
        logDebug(&"recovery: moving in-progress ticket {ticketId} to done (already merged)")
        moveFile(ticketPath, planPath / doneRelPath)

        gitRun(planPath, "add", "-A", PlanTicketsInProgressDir, PlanTicketsDoneDir)
        if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
          let commitMsg = RecoveryMergedCommitPrefix & " " & ticketId
          gitRun(planPath, "commit", "-m", commitMsg)

        logInfo(&"recovery: completed already-merged ticket {ticketId}")
        inc completed

    result = completed
  )

proc reopenOrphanedInProgressTickets*(repoPath: string, caller: string): int =
  ## Step 5: Reopen in-progress tickets that are not merged and not in the merge queue.
  ## At startup no agents are running, so any such ticket was interrupted by a crash.
  if not hasPlanBranch(repoPath):
    return 0

  result = withLockedPlanWorktree(repoPath, caller, proc(planPath: string): int =
    let defaultBranch = resolveDefaultBranch(repoPath)
    var reopened = 0
    let inProgressDir = planPath / PlanTicketsInProgressDir
    if not dirExists(inProgressDir):
      return 0

    # Build set of ticket IDs in the merge queue (pending or active).
    discard ensureMergeQueueInitializedInPlanPath(planPath)
    let queueItems = listMergeQueueItems(planPath)
    var queuedTicketIds: HashSet[string]
    for item in queueItems:
      queuedTicketIds.incl(item.ticketId)

    for ticketPath in listMarkdownFiles(inProgressDir):
      let fileName = extractFilename(ticketPath)
      let ticketId = ticketIdFromTicketPath(fileName)
      let branch = TicketBranchPrefix & ticketId

      # Skip if branch is already merged (completeAlreadyMergedTickets handles this).
      let branchExists = gitCheck(repoPath, "rev-parse", "--verify", branch)
      if branchExists == 0:
        let checkResult = runCommandCapture(
          repoPath, "git", @["merge-base", "--is-ancestor", branch, defaultBranch],
        )
        if checkResult.exitCode == 0:
          continue

      # Skip if ticket is in the merge queue (waiting for merge, not orphaned).
      if ticketId in queuedTicketIds:
        continue

      # Not merged and not queued — reopen by moving back to open.
      let openRelPath = PlanTicketsOpenDir / fileName
      logInfo(&"recovery: reopening orphaned in-progress ticket {ticketId}")
      moveFile(ticketPath, planPath / openRelPath)

      # Clean up the stale worktree if it exists.
      let inProgressRel = PlanTicketsInProgressDir / fileName
      let worktreePath = worktreePathForTicket(repoPath, inProgressRel)
      if dirExists(worktreePath):
        discard gitCheck(repoPath, "worktree", "remove", "--force", worktreePath)
        if dirExists(worktreePath):
          removeDir(worktreePath)
        logDebug(&"recovery: removed stale worktree for {ticketId}")

      gitRun(planPath, "add", "-A", PlanTicketsInProgressDir, PlanTicketsOpenDir)
      if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
        let commitMsg = "scriptorium: recovery — reopen orphaned ticket " & ticketId
        gitRun(planPath, "commit", "-m", commitMsg)

      inc reopened

    result = reopened
  )

proc recoverFromCrash*(repoPath: string, caller: string): RecoverySummary =
  ## Execute the full startup recovery sequence before the first orchestrator tick.
  cleanStaleGitLocks(repoPath)
  result.worktreesCleaned = cleanOrphanedWorktrees(repoPath, caller)
  result.staleMarkersCleared = detectStaleAgentProcesses(repoPath)
  result.planAction = reconcileDirtyPlanBranch(repoPath, caller)
  result.alreadyMergedCompleted = completeAlreadyMergedTickets(repoPath, caller)
  result.orphanedReopened = reopenOrphanedInProgressTickets(repoPath, caller)

  # Step 6: Log recovery summary.
  if result.worktreesCleaned == 0 and result.staleMarkersCleared == 0 and result.planAction == "clean" and result.alreadyMergedCompleted == 0 and result.orphanedReopened == 0:
    logInfo("recovery: clean startup, no recovery needed")
  else:
    let summaryLine = &"recovery: cleaned {result.worktreesCleaned} worktrees, cleared {result.staleMarkersCleared} stale markers, reconciled plan branch ({result.planAction}), completed {result.alreadyMergedCompleted} already-merged tickets, reopened {result.orphanedReopened} orphaned tickets"
    logInfo(summaryLine)

proc buildRecoveryTicketContent*(testOutput: string, commitHash: string): string =
  ## Build the markdown content for a recovery ticket.
  let truncatedOutput = if testOutput.len > MaxRecoveryTestOutputChars:
    testOutput[0 ..< MaxRecoveryTestOutputChars] & "\n\n(output truncated)"
  else:
    testOutput
  let outputSection = if truncatedOutput.len > 0:
    "## Test Failure Output\n\n```\n" & truncatedOutput & "\n```\n"
  else:
    "## Test Failure Output\n\nTest output unavailable (cached result). Run `make test` and `make integration-test` to reproduce the failure.\n"
  result = "# Recovery: Fix Failing Tests on Main Branch\n\n" &
    "**Area:** recovery\n\n" &
    "The main branch tests are failing at commit " & commitHash & ". " &
    "Diagnose the failure from the test output below and fix the root cause. " &
    "Keep the fix minimal and targeted.\n\n" &
    outputSection

proc runRecoveryAgent*(repoPath: string, caller: string, runner: AgentRunner, testOutput: string, commitHash: string) =
  ## Create a recovery ticket and execute it with a coding agent to fix unhealthy main.
  ## Uses the architect model for higher quality fixes.
  let cfg = loadConfig(repoPath)
  let shortHash = if commitHash.len > 7: commitHash[0 ..< 7] else: commitHash
  let ticketContent = buildRecoveryTicketContent(testOutput, shortHash)

  # Create recovery ticket on plan branch.
  let ticketFileName = withLockedPlanWorktree(repoPath, caller, proc(planPath: string): string =
    let ticketId = nextTicketId(planPath)
    let idStr = align($ticketId, 4, '0')
    let fileName = idStr & "-recovery-" & shortHash & ".md"
    let ticketRelPath = PlanTicketsOpenDir / fileName
    let ticketFullPath = planPath / ticketRelPath
    writeFile(ticketFullPath, ticketContent)
    gitRun(planPath, "add", ticketRelPath)
    let commitMsg = RecoveryTicketCommitPrefix & " " & idStr
    gitRun(planPath, "commit", "-m", commitMsg)
    logInfo(&"recovery: created ticket {fileName}")
    fileName
  )

  # Assign and execute. assignOldestOpenTicket picks up the recovery ticket.
  let assignment = assignOldestOpenTicket(repoPath, caller)
  if assignment.inProgressTicket.len == 0:
    logWarn("recovery: failed to assign recovery ticket")
    return

  let ticketId = ticketIdFromTicketPath(assignment.inProgressTicket)
  logInfo(&"recovery: executing recovery agent for {ticketId} (model={cfg.agents.architect.model})")

  # Execute with architect model config for higher quality.
  let agentResult = executeAssignedTicket(repoPath, caller, assignment, runner, cfg.agents.architect)
  if agentResult.submitted:
    logInfo(&"recovery: agent submitted fix for {ticketId}")
  else:
    logWarn(&"recovery: agent did not submit fix for {ticketId}")
