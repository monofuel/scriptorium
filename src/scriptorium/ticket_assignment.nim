import
  std/[algorithm, os, sequtils, sets, strformat, strutils, tables, times, uri],
  ./[config, git_ops, lock_management, logging, merge_queue, shared_state, ticket_analysis, ticket_metadata]

const
  TicketAssignCommitPrefix* = "scriptorium: assign ticket"
  TicketAgentRunCommitPrefix* = "scriptorium: record agent run"
  TicketAgentFailReopenCommitPrefix* = "scriptorium: reopen failed ticket"
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
  discard cleanupLegacyManagedTicketWorktrees(repoPath)
  createDir(parentDir(path))

  discard gitCheck(repoPath, "worktree", "remove", "--force", path)
  if dirExists(path):
    removeDir(path)

  if gitCheck(repoPath, "show-ref", "--verify", "--quiet", "refs/heads/" & branch) == 0:
    gitRun(repoPath, "branch", "-D", branch)
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

proc oldestOpenTicket*(repoPath: string): string =
  ## Return the oldest open ticket path in the plan branch.
  result = withPlanWorktree(repoPath, proc(planPath: string): string =
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

proc isOrchestratorTransitionSubject(subject: string): bool =
  ## Return true when one commit subject is an orchestrator ticket transition commit.
  result =
    subject.startsWith(TicketAssignCommitPrefix & " ") or
    subject.startsWith(MergeQueueDoneCommitPrefix & " ") or
    subject.startsWith(MergeQueueReopenCommitPrefix & " ") or
    subject.startsWith(MergeQueueStuckCommitPrefix & " ") or
    subject.startsWith(TicketAgentFailReopenCommitPrefix & " ")

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

proc listActiveTicketWorktrees*(repoPath: string): seq[ActiveTicketWorktree] =
  ## Return active in-progress ticket worktrees from the plan branch.
  result = withPlanWorktree(repoPath, proc(planPath: string): seq[ActiveTicketWorktree] =
    listActiveTicketWorktreesInPlanPath(planPath)
  )

proc openTicketsByIdInPlanPath(planPath: string): seq[tuple[id: int, rel: string]] =
  ## Return all open tickets sorted by numeric ID (ascending).
  for ticketPath in listMarkdownFiles(planPath / PlanTicketsOpenDir):
    let rel = relativePath(ticketPath, planPath).replace('\\', '/')
    let parsedId = parseInt(ticketIdFromTicketPath(rel))
    result.add((id: parsedId, rel: rel))
  result.sort(proc(a, b: tuple[id: int, rel: string]): int =
    if a.id != b.id: a.id - b.id
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

proc assignOldestOpenTicket*(repoPath: string): TicketAssignment =
  ## Move the oldest assignable open ticket to in-progress and attach a code worktree.
  ## Skips tickets whose dependencies are not yet in done.
  result = withLockedPlanWorktree(repoPath, proc(planPath: string): TicketAssignment =
    let openTickets = openTicketsByIdInPlanPath(planPath)
    if openTickets.len == 0:
      return TicketAssignment()

    let doneIds = doneTicketIdsInPlanPath(planPath)
    var openTicket = ""
    for ticket in openTickets:
      let content = readFile(planPath / ticket.rel)
      if dependenciesSatisfied(content, doneIds):
        openTicket = ticket.rel
        break
    if openTicket.len == 0:
      return TicketAssignment()

    let inProgressTicket = PlanTicketsInProgressDir / splitFile(openTicket).name & ".md"
    let openAbs = planPath / openTicket
    let inProgressAbs = planPath / inProgressTicket
    moveFile(openAbs, inProgressAbs)

    let worktreeInfo = ensureWorktreeCreated(repoPath, inProgressTicket)
    let content = readFile(inProgressAbs)
    writeFile(inProgressAbs, setTicketWorktree(content, worktreeInfo.path))

    gitRun(planPath, "add", "-A", PlanTicketsOpenDir, PlanTicketsInProgressDir)
    if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
      let ticketName = splitFile(inProgressTicket).name
      gitRun(planPath, "commit", "-m", TicketAssignCommitPrefix & " " & ticketName)

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

proc assignOpenTickets*(repoPath: string, maxAgents: int): seq[TicketAssignment] =
  ## Assign multiple open tickets concurrently when they touch independent areas.
  ## Scans open tickets in ID order (oldest first), skipping tickets whose area
  ## already has an in-progress ticket or was claimed earlier in this batch.
  ## Returns a sequence of assignment records for the caller to execute.
  result = withLockedPlanWorktree(repoPath, proc(planPath: string): seq[TicketAssignment] =
    let openTickets = openTicketsByIdInPlanPath(planPath)
    if openTickets.len == 0:
      return @[]

    var occupiedAreas = inProgressAreasInPlanPath(planPath)
    let doneIds = doneTicketIdsInPlanPath(planPath)
    var assignments: seq[TicketAssignment]

    for ticket in openTickets:
      if assignments.len >= maxAgents:
        break

      let content = readFile(planPath / ticket.rel)
      let areaId = parseAreaFromTicketContent(content)

      if areaId.len > 0 and areaId in occupiedAreas:
        continue

      if not dependenciesSatisfied(content, doneIds):
        continue

      let inProgressTicket = PlanTicketsInProgressDir / splitFile(ticket.rel).name & ".md"
      let openAbs = planPath / ticket.rel
      let inProgressAbs = planPath / inProgressTicket
      moveFile(openAbs, inProgressAbs)

      let worktreeInfo = ensureWorktreeCreated(repoPath, inProgressTicket)
      let updatedContent = readFile(inProgressAbs)
      writeFile(inProgressAbs, setTicketWorktree(updatedContent, worktreeInfo.path))

      if areaId.len > 0:
        occupiedAreas.incl(areaId)

      let ticketId = ticketIdFromTicketPath(inProgressTicket)
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
      gitRun(planPath, "add", "-A", PlanTicketsOpenDir, PlanTicketsInProgressDir)
      if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
        let ticketNames = assignments.mapIt(splitFile(it.inProgressTicket).name).join(", ")
        gitRun(planPath, "commit", "-m", TicketAssignCommitPrefix & " " & ticketNames)

    result = assignments
  )

proc cleanupStaleTicketWorktrees*(repoPath: string): seq[string] =
  ## Remove managed code worktrees that no longer correspond to in-progress tickets.
  let managedRoot = normalizeAbsolutePath(managedTicketWorktreeRootPath(repoPath))
  for path in cleanupLegacyManagedTicketWorktrees(repoPath):
    result.add(path)

  let activeWorktrees = withLockedPlanWorktree(repoPath, proc(planPath: string): HashSet[string] =
    result = initHashSet[string]()
    for ticketPath in listMarkdownFiles(planPath / PlanTicketsInProgressDir):
      let worktreePath = parseWorktreeFromTicketContent(readFile(ticketPath))
      if worktreePath.len > 0:
        result.incl(worktreePath)
  )

  for path in listGitWorktreePaths(repoPath):
    let normalizedPath = normalizeAbsolutePath(path)
    if normalizedPath.startsWith(managedRoot & "/") and not activeWorktrees.contains(path):
      discard gitCheck(repoPath, "worktree", "remove", "--force", path)
      if dirExists(path):
        removeDir(path)
      result.add(path)

proc readOrchestratorStatus*(repoPath: string): OrchestratorStatus =
  ## Return plan ticket counts and current active agent metadata.
  result = withPlanWorktree(repoPath, proc(planPath: string): OrchestratorStatus =
    result = OrchestratorStatus(
      openTickets: listMarkdownFiles(planPath / PlanTicketsOpenDir).len,
      inProgressTickets: listMarkdownFiles(planPath / PlanTicketsInProgressDir).len,
      doneTickets: listMarkdownFiles(planPath / PlanTicketsDoneDir).len,
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
  )

proc validateTicketStateInvariant*(repoPath: string) =
  ## Validate that no ticket markdown filename exists in more than one state directory.
  discard withPlanWorktree(repoPath, proc(planPath: string): int =
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
