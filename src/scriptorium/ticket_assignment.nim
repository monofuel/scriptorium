import
  std/[algorithm, os, posix, sequtils, sets, strformat, strutils, tables, times, uri],
  ./[config, cycle_detection, git_ops, journal, lock_management, logging, merge_queue, output_formatting, shared_state, ticket_metadata]

const
  TicketAssignCommitPrefix* = "scriptorium: assign ticket"
  TicketAgentRunCommitPrefix* = "scriptorium: record agent run"
  TicketAgentFailReopenCommitPrefix* = "scriptorium: reopen failed ticket"
  TicketUnstickCommitPrefix* = "scriptorium: unstick ticket"
  MergeQueueDoneCommitPrefix = "scriptorium: complete ticket"
  MergeQueueReopenCommitPrefix = "scriptorium: reopen ticket"
  MergeQueueStuckCommitPrefix = "scriptorium: park stuck ticket"

proc branchNameForTicket*(ticketRelPath: string): string =
  ## Build a deterministic branch name for a ticket.
  result = TicketBranchPrefix & ticketIdFromTicketPath(ticketRelPath)

proc worktreePathForTicket*(repoPath: string, ticketRelPath: string): string =
  ## Build a deterministic absolute worktree path for a ticket.
  let ticketName = splitFile(ticketRelPath).name
  let root = managedTicketWorktreeRootPath(repoPath)
  result = absolutePath(root / ticketName)

proc ensureWorktreeCreated*(repoPath: string, ticketRelPath: string): tuple[branch: string, path: string] =
  ## Ensure the code worktree exists for the ticket and return branch/path.
  let branch = branchNameForTicket(ticketRelPath)
  let path = worktreePathForTicket(repoPath, ticketRelPath)
  createDir(parentDir(path))

  # Unlock first — a locked worktree cannot be removed with single --force.
  discard gitCheck(repoPath, "worktree", "unlock", path)
  discard gitCheck(repoPath, "worktree", "remove", "--force", path)
  discard gitCheck(repoPath, "worktree", "prune")
  if dirExists(path):
    forceRemoveDir(path)

  if gitCheck(repoPath, "show-ref", "--verify", "--quiet", "refs/heads/" & branch) == 0:
    let branchRc = gitCheck(repoPath, "branch", "-D", branch)
    if branchRc != 0:
      logWarn(&"branch -D {branch} failed (rc={branchRc}), continuing anyway")
  gitRun(repoPath, "worktree", "add", "-b", branch, path)

  result = (branch: branch, path: path)

proc oldestOpenTicketInPlanPath*(planPath: string): string =
  ## Return the oldest open ticket path relative to planPath.
  var bestId = high(int)
  var bestRel = ""
  for ticketPath in listMarkdownFiles(planPath / PlanTicketsOpenDir):
    let rel = relativePath(ticketPath, planPath).replace('\\', '/')
    let parsedId = parseInt(ticketIdFromTicketPath(rel))
    if parsedId < bestId or (parsedId == bestId and rel < bestRel):
      bestId = parsedId
      bestRel = rel
  result = bestRel

proc oldestOpenTicket*(repoPath: string, caller: string): string =
  ## Return the oldest open ticket path in the plan branch.
  result = withPlanWorktree(repoPath, caller, proc(planPath: string): string =
    oldestOpenTicketInPlanPath(planPath)
  )

proc ensureUniqueTicketStateInPlanPath*(planPath: string) =
  ## Ensure each ticket markdown filename exists in exactly one state directory.
  var seen = initHashSet[string]()
  for stateDir in [PlanTicketsOpenDir, PlanTicketsInProgressDir, PlanTicketsDoneDir, PlanTicketsStuckDir]:
    for ticketPath in listMarkdownFiles(planPath / stateDir):
      let fileName = extractFilename(ticketPath)
      if seen.contains(fileName):
        raise newException(ValueError, fmt"ticket exists in multiple state directories: {fileName}")
      seen.incl(fileName)

proc ticketStateFromPath(path: string): string =
  ## Return ticket state directory name from one ticket markdown path.
  let normalized = path.replace('\\', '/')
  if normalized.startsWith(PlanTicketsOpenDir & "/"):
    result = PlanTicketsOpenDir
  elif normalized.startsWith(PlanTicketsInProgressDir & "/"):
    result = PlanTicketsInProgressDir
  elif normalized.startsWith(PlanTicketsDoneDir & "/"):
    result = PlanTicketsDoneDir
  elif normalized.startsWith(PlanTicketsStuckDir & "/"):
    result = PlanTicketsStuckDir

proc isOrchestratorTransitionSubject(subject: string): bool =
  ## Return true when one commit subject is an orchestrator ticket transition commit.
  result =
    subject.startsWith(TicketAssignCommitPrefix & " ") or
    subject.startsWith(MergeQueueDoneCommitPrefix & " ") or
    subject.startsWith(MergeQueueReopenCommitPrefix & " ") or
    subject.startsWith(MergeQueueStuckCommitPrefix & " ") or
    subject.startsWith(TicketAgentFailReopenCommitPrefix & " ") or
    subject.startsWith(TicketUnstickCommitPrefix & " ")

proc transitionCountInCommit(repoPath: string, parentCommit: string, commitHash: string): int =
  ## Count ticket state transitions represented by one commit diff.
  let diffResult = runCommandCapture(
    repoPath,
    "git",
    @[
      "diff",
      "--name-status",
      "--find-renames",
      parentCommit,
      commitHash,
      "--",
      PlanTicketsOpenDir,
      PlanTicketsInProgressDir,
      PlanTicketsDoneDir,
      PlanTicketsStuckDir,
    ],
  )
  if diffResult.exitCode != 0:
    raise newException(IOError, fmt"git diff failed while auditing transitions: {diffResult.output.strip()}")

  var removedByName = initTable[string, string]()
  var addedByName = initTable[string, string]()
  for line in diffResult.output.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue
    let columns = trimmed.split('\t')
    if columns.len < 2:
      continue

    let status = columns[0]
    if status.startsWith("R"):
      if columns.len < 3:
        continue
      let oldPath = columns[1]
      let newPath = columns[2]
      let oldState = ticketStateFromPath(oldPath)
      let newState = ticketStateFromPath(newPath)
      let oldName = extractFilename(oldPath)
      let newName = extractFilename(newPath)
      if oldState.len > 0 and newState.len > 0 and oldState != newState:
        if oldName != newName:
          raise newException(ValueError, fmt"invalid ticket rename across states in commit {commitHash}: {oldPath} -> {newPath}")
        inc result
    elif status == "D":
      let oldPath = columns[1]
      let oldState = ticketStateFromPath(oldPath)
      if oldState.len > 0:
        removedByName[extractFilename(oldPath)] = oldState
    elif status == "A":
      let newPath = columns[1]
      let newState = ticketStateFromPath(newPath)
      if newState.len > 0:
        addedByName[extractFilename(newPath)] = newState

  for ticketName, oldState in removedByName.pairs():
    if addedByName.hasKey(ticketName):
      let newState = addedByName[ticketName]
      if oldState != newState:
        inc result

proc listActiveTicketWorktreesInPlanPath*(planPath: string): seq[ActiveTicketWorktree] =
  ## Return active in-progress ticket worktrees from a plan worktree path.
  for ticketPath in listMarkdownFiles(planPath / PlanTicketsInProgressDir):
    let relPath = relativePath(ticketPath, planPath).replace('\\', '/')
    let content = readFile(ticketPath)
    result.add(ActiveTicketWorktree(
      ticketPath: relPath,
      ticketId: ticketIdFromTicketPath(relPath),
      branch: branchNameForTicket(relPath),
      worktree: parseWorktreeFromTicketContent(content),
    ))
  result.sort(proc(a: ActiveTicketWorktree, b: ActiveTicketWorktree): int = cmp(a.ticketPath, b.ticketPath))

proc listActiveTicketWorktrees*(repoPath: string, caller: string): seq[ActiveTicketWorktree] =
  ## Return active in-progress ticket worktrees from the plan branch.
  result = withPlanWorktree(repoPath, caller, proc(planPath: string): seq[ActiveTicketWorktree] =
    listActiveTicketWorktreesInPlanPath(planPath)
  )

proc priorityOrd(p: TicketPriority): int =
  ## Return sort order for priority (higher value = runs first).
  case p
  of tpCritical: 3
  of tpHigh: 2
  of tpMedium: 1
  of tpLow: 0

proc openTicketsByIdInPlanPath(planPath: string, areaFilter: string = ""): seq[tuple[id: int, rel: string, priority: TicketPriority]] =
  ## Return open tickets sorted by priority (critical first) then numeric ID (ascending).
  ## When areaFilter is non-empty, only tickets matching that area are returned.
  for ticketPath in listMarkdownFiles(planPath / PlanTicketsOpenDir):
    let rel = relativePath(ticketPath, planPath).replace('\\', '/')
    let content = readFile(ticketPath)
    if areaFilter.len > 0:
      let area = parseAreaFromTicketContent(content)
      if area != areaFilter:
        continue
    let parsedId = parseInt(ticketIdFromTicketPath(rel))
    let priority = parsePriorityFromTicketContent(content)
    result.add((id: parsedId, rel: rel, priority: priority))
  result.sort(proc(a, b: tuple[id: int, rel: string, priority: TicketPriority]): int =
    let pa = priorityOrd(a.priority)
    let pb = priorityOrd(b.priority)
    if pa != pb: pb - pa
    elif a.id != b.id: a.id - b.id
    else: cmp(a.rel, b.rel)
  )

proc inProgressAreasInPlanPath(planPath: string): HashSet[string] =
  ## Collect area identifiers from in-progress tickets.
  result = initHashSet[string]()
  for ticketPath in listMarkdownFiles(planPath / PlanTicketsInProgressDir):
    let areaId = parseAreaFromTicketContent(readFile(ticketPath))
    if areaId.len > 0:
      result.incl(areaId)

proc doneTicketIdsInPlanPath(planPath: string): HashSet[string] =
  ## Collect ticket IDs from done tickets.
  result = initHashSet[string]()
  for ticketPath in listMarkdownFiles(planPath / PlanTicketsDoneDir):
    let rel = PlanTicketsDoneDir / extractFilename(ticketPath)
    result.incl(ticketIdFromTicketPath(rel))

proc assignOldestOpenTicket*(repoPath: string, caller: string, areaFilter: string = ""): TicketAssignment =
  ## Move the oldest assignable open ticket to in-progress and attach a code worktree.
  ## Skips tickets whose dependencies are not yet in done.
  ## When areaFilter is non-empty, only tickets matching that area are considered.
  result = withLockedPlanWorktree(repoPath, caller, proc(planPath: string): TicketAssignment =
    let openTickets = openTicketsByIdInPlanPath(planPath, areaFilter)
    if openTickets.len == 0:
      return TicketAssignment()

    let doneIds = doneTicketIdsInPlanPath(planPath)
    var repairedGraph = buildRepairedDependencyGraph(planPath)
    var openTicket = ""
    for ticket in openTickets:
      let ticketId = ticketIdFromTicketPath(ticket.rel)
      let repairedDeps = repairedGraph.getOrDefault(ticketId, @[])
      let allSatisfied = repairedDeps.allIt(it in doneIds)
      if allSatisfied:
        openTicket = ticket.rel
        break
      else:
        let unsatisfied = repairedDeps.filterIt(it notin doneIds)
        logDebug(&"ticket {ticketId}: skipping assignment, unsatisfied deps: {unsatisfied}")
    if openTicket.len == 0:
      if openTickets.len > 0:
        let count = openTickets.len
        logWarn(&"assignment: {count} open ticket(s) but none assignable (all have unsatisfied dependencies)")
      return TicketAssignment()

    let inProgressTicket = PlanTicketsInProgressDir / splitFile(openTicket).name & ".md"
    let content = readFile(planPath / openTicket)
    let worktreeInfo = ensureWorktreeCreated(repoPath, inProgressTicket)
    let updatedContent = setTicketWorktree(content, worktreeInfo.path)
    let ticketName = splitFile(inProgressTicket).name
    let commitMsg = TicketAssignCommitPrefix & " " & ticketName
    let steps = @[
      newMoveStep(openTicket, inProgressTicket),
      newWriteStep(inProgressTicket, updatedContent),
    ]
    beginJournalTransition(planPath, "assign " & ticketName, steps, commitMsg)
    executeJournalSteps(planPath)
    completeJournalTransition(planPath)

    let ticketId = ticketIdFromTicketPath(inProgressTicket)
    logInfo(fmt"ticket {ticketId}: open -> in-progress (assigned, worktree={worktreeInfo.path})")
    ticketStartTimes[ticketId] = epochTime()
    ticketAttemptCounts[ticketId] = 0
    ticketCodingWalls[ticketId] = 0.0
    ticketTestWalls[ticketId] = 0.0
    ticketModels[ticketId] = ""
    ticketStdoutBytes[ticketId] = 0

    result = TicketAssignment(
      openTicket: openTicket,
      inProgressTicket: inProgressTicket,
      branch: worktreeInfo.branch,
      worktree: worktreeInfo.path,
    )
  )

proc assignOpenTickets*(repoPath: string, caller: string, maxAgents: int, areaFilter: string = ""): seq[TicketAssignment] =
  ## Assign multiple open tickets concurrently when they touch independent areas.
  ## Scans open tickets in ID order (oldest first), skipping tickets whose area
  ## already has an in-progress ticket or was claimed earlier in this batch.
  ## When areaFilter is non-empty, only tickets matching that area are considered.
  ## Returns a sequence of assignment records for the caller to execute.
  result = withLockedPlanWorktree(repoPath, caller, proc(planPath: string): seq[TicketAssignment] =
    let openTickets = openTicketsByIdInPlanPath(planPath, areaFilter)
    if openTickets.len == 0:
      return @[]

    var occupiedAreas = inProgressAreasInPlanPath(planPath)
    let doneIds = doneTicketIdsInPlanPath(planPath)
    var repairedGraph = buildRepairedDependencyGraph(planPath)
    var assignments: seq[TicketAssignment]
    var journalSteps: seq[JournalStep]

    for ticket in openTickets:
      if assignments.len >= maxAgents:
        break

      let content = readFile(planPath / ticket.rel)
      let areaId = parseAreaFromTicketContent(content)

      if areaId.len > 0 and areaId in occupiedAreas:
        continue

      let ticketId = ticketIdFromTicketPath(ticket.rel)
      let repairedDeps = repairedGraph.getOrDefault(ticketId, @[])
      if not repairedDeps.allIt(it in doneIds):
        let unsatisfied = repairedDeps.filterIt(it notin doneIds)
        logDebug(&"ticket {ticketId}: skipping assignment, unsatisfied deps: {unsatisfied}")
        continue

      let inProgressTicket = PlanTicketsInProgressDir / splitFile(ticket.rel).name & ".md"
      let worktreeInfo = ensureWorktreeCreated(repoPath, inProgressTicket)
      let updatedContent = setTicketWorktree(content, worktreeInfo.path)
      journalSteps.add(newMoveStep(ticket.rel, inProgressTicket))
      journalSteps.add(newWriteStep(inProgressTicket, updatedContent))

      if areaId.len > 0:
        occupiedAreas.incl(areaId)

      logInfo(fmt"ticket {ticketId}: open -> in-progress (assigned, worktree={worktreeInfo.path})")
      ticketStartTimes[ticketId] = epochTime()
      ticketAttemptCounts[ticketId] = 0
      ticketCodingWalls[ticketId] = 0.0
      ticketTestWalls[ticketId] = 0.0
      ticketModels[ticketId] = ""
      ticketStdoutBytes[ticketId] = 0

      assignments.add(TicketAssignment(
        openTicket: ticket.rel,
        inProgressTicket: inProgressTicket,
        branch: worktreeInfo.branch,
        worktree: worktreeInfo.path,
      ))

    if assignments.len > 0:
      let ticketNames = assignments.mapIt(splitFile(it.inProgressTicket).name).join(", ")
      let commitMsg = TicketAssignCommitPrefix & " " & ticketNames
      beginJournalTransition(planPath, "assign " & ticketNames, journalSteps, commitMsg)
      executeJournalSteps(planPath)
      completeJournalTransition(planPath)

    result = assignments
  )

proc cleanupStaleTicketWorktrees*(repoPath: string, caller: string): seq[string] =
  ## Remove managed code worktrees that no longer correspond to in-progress tickets.
  let managedRoot = normalizeAbsolutePath(managedTicketWorktreeRootPath(repoPath))
  let activeWorktrees = withLockedPlanWorktree(repoPath, caller, proc(planPath: string): HashSet[string] =
    result = initHashSet[string]()
    for ticketPath in listMarkdownFiles(planPath / PlanTicketsInProgressDir):
      let worktreePath = parseWorktreeFromTicketContent(readFile(ticketPath))
      if worktreePath.len > 0:
        result.incl(worktreePath)
  )

  for path in listGitWorktreePaths(repoPath):
    let normalizedPath = normalizeAbsolutePath(path)
    if normalizedPath.startsWith(managedRoot & "/") and not activeWorktrees.contains(path):
      # Unlock first — a locked worktree cannot be removed with single --force.
      discard gitCheck(repoPath, "worktree", "unlock", path)
      discard gitCheck(repoPath, "worktree", "remove", "--force", path)
      discard gitCheck(repoPath, "worktree", "prune")
      if dirExists(path):
        forceRemoveDir(path)
      result.add(path)

proc worktreeElapsed(worktreePath: string): string =
  ## Return formatted elapsed time since worktree creation, or empty string if unavailable.
  if worktreePath.len == 0 or not dirExists(worktreePath):
    return ""
  var statBuf: Stat
  if stat(worktreePath.cstring, statBuf) == 0:
    let createdAt = statBuf.st_ctime.float
    let elapsed = epochTime() - createdAt
    if elapsed >= 0:
      return formatDuration(elapsed)
  return ""

const
  DefaultRecentDoneCount = 5

proc readOrchestratorStatus*(repoPath: string, caller: string): OrchestratorStatus =
  ## Return plan ticket counts, active agent metadata, elapsed times, recent done tickets, and first-attempt success rate.
  result = withPlanWorktree(repoPath, caller, proc(planPath: string): OrchestratorStatus =
    result = OrchestratorStatus(
      openTickets: listMarkdownFiles(planPath / PlanTicketsOpenDir).len,
      inProgressTickets: listMarkdownFiles(planPath / PlanTicketsInProgressDir).len,
      doneTickets: listMarkdownFiles(planPath / PlanTicketsDoneDir).len,
      stuckTickets: listMarkdownFiles(planPath / PlanTicketsStuckDir).len,
    )

    let activeQueuePath = planPath / PlanMergeQueueActivePath
    if fileExists(activeQueuePath):
      let activeRelPath = readFile(activeQueuePath).strip()
      if activeRelPath.len > 0:
        let pendingPath = planPath / activeRelPath
        if fileExists(pendingPath):
          let item = parseMergeQueueItem(activeRelPath, readFile(pendingPath))
          result.activeTicketPath = item.ticketPath
          result.activeTicketId = item.ticketId
          result.activeTicketBranch = item.branch
          result.activeTicketWorktree = item.worktree

    if result.activeTicketId.len == 0:
      let activeWorktrees = listActiveTicketWorktreesInPlanPath(planPath)
      if activeWorktrees.len > 0:
        let active = activeWorktrees[0]
        result.activeTicketPath = active.ticketPath
        result.activeTicketId = active.ticketId
        result.activeTicketBranch = active.branch
        result.activeTicketWorktree = active.worktree

    for ticketPath in listMarkdownFiles(planPath / PlanTicketsInProgressDir):
      let relPath = relativePath(ticketPath, planPath).replace('\\', '/')
      let ticketId = ticketIdFromTicketPath(relPath)
      let content = readFile(ticketPath)
      let wtPath = parseWorktreeFromTicketContent(content)
      let elapsed = worktreeElapsed(wtPath)
      if elapsed.len > 0:
        result.inProgressElapsed.add(InProgressTicketElapsed(
          ticketId: ticketId,
          elapsed: elapsed,
        ))

    let doneFiles = listMarkdownFiles(planPath / PlanTicketsDoneDir)
    var firstAttemptCount = 0
    var totalWithAttempts = 0
    var doneSummaries: seq[DoneTicketSummary]
    for ticketPath in doneFiles:
      let relPath = relativePath(ticketPath, planPath).replace('\\', '/')
      let ticketId = ticketIdFromTicketPath(relPath)
      let content = readFile(ticketPath)
      let outcome = parseMetricField(content, "outcome")
      let wallStr = parseMetricField(content, "wall_time_seconds")
      let attemptStr = parseMetricField(content, "attempt_count")
      var wallSecs = 0
      if wallStr.len > 0:
        wallSecs = parseInt(wallStr)
      doneSummaries.add(DoneTicketSummary(
        ticketId: ticketId,
        outcome: outcome,
        wallTimeSeconds: wallSecs,
      ))
      if attemptStr.len > 0:
        totalWithAttempts += 1
        if parseInt(attemptStr) == 1:
          firstAttemptCount += 1

    doneSummaries.sort(proc(a, b: DoneTicketSummary): int =
      cmp(b.ticketId, a.ticketId)
    )
    if doneSummaries.len > DefaultRecentDoneCount:
      doneSummaries.setLen(DefaultRecentDoneCount)
    result.recentDoneTickets = doneSummaries
    result.firstAttemptSuccessCount = firstAttemptCount
    result.totalDoneWithAttempts = totalWithAttempts

    var repairedGraph = buildRepairedDependencyGraph(planPath)
    let doneIds = doneTicketIdsInPlanPath(planPath)
    for stateDir in [PlanTicketsOpenDir, PlanTicketsInProgressDir]:
      for ticketPath in listMarkdownFiles(planPath / stateDir):
        let rel = stateDir / extractFilename(ticketPath)
        let ticketId = ticketIdFromTicketPath(rel)
        let deps = repairedGraph.getOrDefault(ticketId, @[])
        if deps.len == 0:
          continue
        var unsatisfied: seq[string]
        for dep in deps:
          if dep notin doneIds:
            unsatisfied.add(dep)
        if unsatisfied.len > 0:
          result.waitingTickets.add(WaitingTicket(ticketId: ticketId, dependsOn: unsatisfied))
  )

proc validateTicketStateInvariant*(repoPath: string, caller: string) =
  ## Validate that no ticket markdown filename exists in more than one state directory.
  discard withPlanWorktree(repoPath, caller, proc(planPath: string): int =
    ensureUniqueTicketStateInPlanPath(planPath)
    0
  )

proc validateTransitionCommitInvariant*(repoPath: string) =
  ## Validate that each ticket state transition is exactly one orchestrator transition commit.
  let logResult = runCommandCapture(
    repoPath,
    "git",
    @["log", "--reverse", "--format=%H%x1f%P%x1f%s", PlanBranch],
  )
  if logResult.exitCode != 0:
    raise newException(IOError, fmt"git log failed while auditing transitions: {logResult.output.strip()}")

  for line in logResult.output.splitLines():
    if line.strip().len == 0:
      continue
    let columns = line.split('\x1f')
    if columns.len < 3:
      raise newException(ValueError, fmt"invalid git log row while auditing transitions: {line}")

    let commitHash = columns[0].strip()
    let parentValue = columns[1].strip()
    let subject = columns[2].strip()
    let isTransitionSubject = isOrchestratorTransitionSubject(subject)

    if parentValue.len == 0:
      if isTransitionSubject:
        raise newException(ValueError, fmt"transition commit cannot be root commit: {subject}")
      continue

    let parentCommit = parentValue.splitWhitespace()[0]
    let transitionCount = transitionCountInCommit(repoPath, parentCommit, commitHash)
    if transitionCount > 0 and not isTransitionSubject:
      raise newException(ValueError, fmt"ticket state transition must use orchestrator transition commit: {subject}")
    if isTransitionSubject and transitionCount != 1:
      raise newException(
        ValueError,
        fmt"orchestrator transition commit must contain exactly one ticket transition: {subject} (found {transitionCount})",
      )

proc parseEndpoint*(endpointUrl: string): OrchestratorEndpoint =
  ## Parse the orchestrator HTTP endpoint from a URL.
  let clean = endpointUrl.strip()
  let resolved = if clean.len > 0: clean else: DefaultLocalEndpoint
  let parsed = parseUri(resolved)

  if parsed.scheme.len == 0:
    raise newException(ValueError, fmt"invalid endpoint URL (missing scheme): {resolved}")
  if parsed.hostname.len == 0:
    raise newException(ValueError, fmt"invalid endpoint URL (missing hostname): {resolved}")

  var port: int
  if parsed.port.len > 0:
    port = parseInt(parsed.port)
  elif parsed.scheme == "https":
    port = 443
  else:
    port = 80

  if port < 1 or port > 65535:
    raise newException(ValueError, fmt"invalid endpoint port: {port}")

  result = OrchestratorEndpoint(
    address: parsed.hostname,
    port: port,
  )

proc loadOrchestratorEndpoint*(repoPath: string): OrchestratorEndpoint =
  ## Load and parse the orchestrator endpoint from repo configuration.
  let cfg = loadConfig(repoPath)
  result = parseEndpoint(cfg.endpoints.local)

proc recoverStuckTickets*(repoPath: string, caller: string): int =
  ## Move recoverable stuck tickets back to open for retry.
  ## A ticket is recoverable if its stuck count is below MaxStuckCount.
  ## Returns the number of tickets recovered.
  result = withPlanWorktree(repoPath, caller, proc(planPath: string): int =
    let stuckFiles = listMarkdownFiles(planPath / PlanTicketsStuckDir)
    var recovered = 0
    for ticketPath in stuckFiles:
      let content = readFile(ticketPath)
      let stuckCount = parseStuckCount(content)
      if stuckCount >= MaxStuckCount:
        continue
      let filename = extractFilename(ticketPath)
      let ticketId = ticketIdFromTicketPath(PlanTicketsStuckDir / filename)
      let openRelPath = PlanTicketsOpenDir / filename
      let commitMsg = TicketUnstickCommitPrefix & " " & ticketId
      let steps = @[
        newMoveStep(PlanTicketsStuckDir / filename, openRelPath),
      ]
      beginJournalTransition(planPath, "unstick " & ticketId, steps, commitMsg)
      executeJournalSteps(planPath)
      completeJournalTransition(planPath)
      logInfo(&"recovered stuck ticket {ticketId} (stuck count {stuckCount})")
      recovered += 1
    recovered
  )
