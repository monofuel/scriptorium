import
  std/[algorithm, httpclient, json, locks, math, os, osproc, posix, sequtils, sets, sha1, streams, strformat, strutils, tables, times, uri],
  mcport,
  ./[agent_runner, config, logging, prompt_catalog]

const
  PlanBranch = "scriptorium/plan"
  PlanAreasDir = "areas"
  PlanTicketsOpenDir = "tickets/open"
  PlanTicketsInProgressDir = "tickets/in-progress"
  PlanTicketsDoneDir = "tickets/done"
  PlanMergeQueueDir = "queue/merge"
  PlanMergeQueuePendingDir = "queue/merge/pending"
  PlanMergeQueueActivePath = "queue/merge/active.md"
  PlanSpecPath = "spec.md"
  PlanSpecPlaceholder = "# Spec\n\nRun `scriptorium plan` to build your spec with the Architect."
  AreaCommitMessage = "scriptorium: update areas from spec"
  TicketCommitMessage = "scriptorium: create tickets from areas"
  AreaFieldPrefix = "**Area:**"
  DependsFieldPrefix = "**Depends:**"
  WorktreeFieldPrefix = "**Worktree:**"
  TicketAssignCommitPrefix = "scriptorium: assign ticket"
  TicketAgentRunCommitPrefix = "scriptorium: record agent run"
  MergeQueueInitCommitMessage = "scriptorium: initialize merge queue"
  MergeQueueEnqueueCommitPrefix = "scriptorium: enqueue merge request"
  MergeQueueDoneCommitPrefix = "scriptorium: complete ticket"
  MergeQueueReopenCommitPrefix = "scriptorium: reopen ticket"
  MergeQueueCleanupCommitPrefix = "scriptorium: cleanup merge queue"
  MergeQueueStuckCommitPrefix = "scriptorium: park stuck ticket"
  TicketAgentFailReopenCommitPrefix = "scriptorium: reopen failed ticket"
  HealthCacheDir = "health"
  HealthCacheFileName = "cache.json"
  HealthCacheRelPath = "health/cache.json"
  HealthCacheCommitMessage = "scriptorium: update health cache"
  PlanTicketsStuckDir = "tickets/stuck"
  MaxMergeFailures = 3
  PlanSpecCommitMessage = "scriptorium: update spec from architect"
  PlanSpecTicketId = "plan-spec"
  PlanSessionTicketId = "plan-session"
  AskSessionTicketId = "ask-session"
  ManagedStateRootDirName = "scriptorium"
  ManagedWorktreeDirName = "worktrees"
  ManagedPlanWorktreeName = "plan"
  ManagedMasterWorktreeName = "master"
  ManagedTicketWorktreeDirName = "tickets"
  ManagedLockDirName = "locks"
  ManagedRepoLockName = "repo.lock"
  ManagedRepoLockPidFileName = "pid"
  LegacyManagedWorktreeRoot = ".scriptorium/worktrees"
  PlanLogRoot = "scriptorium-plan-logs"
  PlanWriteScopeName = "scriptorium plan"
  AskWriteScopeName = "scriptorium ask"
  ManagerWriteScopeName = "scriptorium manager"
  ArchitectAreasLogDirName = "architect-areas"
  ManagerLogDirName = "manager"
  TicketBranchPrefix = "scriptorium/ticket-"
  DefaultLocalEndpoint* = "http://127.0.0.1:8097"
  DefaultAgentAttempt = 1
  PlanDefaultMaxAttempts = 1
  PlanNoOutputTimeoutMs = 120_000
  PlanHardTimeoutMs = 300_000
  PlanHeartbeatIntervalMs = 3000
  PlanStreamPreviewChars = 140
  DefaultAgentMaxAttempts = 2
  AgentMessagePreviewChars = 1200
  AgentStdoutPreviewChars = 1200
  MergeQueueOutputPreviewChars = 2000
  RequiredQualityTargets = ["test", "integration-test"]
  GitCommandTimeoutMs = 60_000
  QualityCheckTimeoutMs = 300_000
  IdleSleepMs = 200
  IdleBackoffSleepMs = 30_000
  WaitingNoSpecMessage = "WAITING: no spec — run 'scriptorium plan'"
  ArchitectAreasTicketId = "architect-areas"
  ManagerTicketIdPrefix = "manager-"
  OrchestratorServerName = "scriptorium-orchestrator"
  OrchestratorServerVersion = "0.1.0"
  BuildCommitHash {.strdefine.} = "unknown"
  SpecHashMarkerPath = "areas/.spec-hash"
  AreaHashesPath = "tickets/.area-hashes"
  SpecHashCommitMessage = "scriptorium: update spec hash marker"
  AreaHashesCommitMessage = "scriptorium: update area hashes"
  SubmitPrSummaryMaxBytes = 4096
  SubmitPrTestOutputMaxChars = 2000
  ActiveWorktreePathMaxBytes = 1024
  ActiveTicketIdMaxBytes = 256
  ReviewActionMaxBytes = 32
  ReviewFeedbackMaxBytes = 4096
  StallContinuationText = "The previous attempt exited cleanly without calling the `submit_pr` MCP tool.\nThis is a stall — the agent exited without completing the ticket.\nContinue working on the ticket and call `submit_pr` with a summary when done."
  StallTestOutputMaxBytes = 8192
  RateLimitBaseBackoffSeconds = 2.0
  RateLimitMaxBackoffSeconds = 120.0
  RateLimitBackoffMultiplier = 2.0
  MakeTestTimeoutMs = 300_000
  PredictionNoOutputTimeoutMs = 30_000
  PredictionHardTimeoutMs = 60_000
  PredictionCommitPrefix = "scriptorium: predict ticket"
  PostAnalysisCommitPrefix = "scriptorium: post-analysis ticket"
  ReviewAgentNoOutputTimeoutMs = 120_000
  ReviewAgentHardTimeoutMs = 300_000
  ReviewAgentCommitPrefix = "scriptorium: review ticket"
  ServerReadyTimeoutMs = 5000
  ServerReadyPollIntervalMs = 50

type
  OrchestratorEndpoint* = object
    address*: string
    port*: int

  AreaDocument* = object
    path*: string
    content*: string

  ArchitectAreaGenerator* = proc(model: string, spec: string): seq[AreaDocument]

  TicketDocument* = object
    slug*: string
    content*: string

  ManagerTicketGenerator* = proc(model: string, areaPath: string, areaContent: string): seq[TicketDocument]

  PlanTurn* = object
    role*: string
    text*: string

  PlanSessionInput* = proc(): string
    ## Returns the next line of input. Raises EOFError to end the session.

  TicketAssignment* = object
    openTicket*: string
    inProgressTicket*: string
    branch*: string
    worktree*: string

  ActiveTicketWorktree* = object
    ticketPath*: string
    ticketId*: string
    branch*: string
    worktree*: string

  OrchestratorStatus* = object
    openTickets*: int
    inProgressTickets*: int
    doneTickets*: int
    activeTicketPath*: string
    activeTicketId*: string
    activeTicketBranch*: string
    activeTicketWorktree*: string

  MergeQueueItem* = object
    pendingPath*: string
    ticketPath*: string
    ticketId*: string
    branch*: string
    worktree*: string
    summary*: string

  ServerThreadArgs = tuple[
    httpServer: HttpMcpServer,
    address: string,
    port: int,
  ]

  MasterHealthState = object
    head*: string
    healthy*: bool
    initialized*: bool
    lastHealthLogged*: bool

  HealthCacheEntry* = object
    healthy*: bool
    timestamp*: string
    test_exit_code*: int
    integration_test_exit_code*: int
    test_wall_seconds*: int
    integration_test_wall_seconds*: int

  SessionStats* = object
    startTime*: float
    totalTicks*: int
    ticketsCompleted*: int
    ticketsReopened*: int
    ticketsParked*: int
    mergeQueueProcessed*: int
    firstAttemptSuccessCount*: int
    completedTicketWalls*: seq[float]
    completedCodingWalls*: seq[float]
    completedTestWalls*: seq[float]

  AgentSlot* = object
    ticketId*: string
    branch*: string
    worktree*: string
    startTime*: float

  AgentThreadArgs = tuple[
    repoPath: string,
    assignment: TicketAssignment,
    ticketId: string,
  ]

  AgentCompletionResult = tuple[
    ticketId: string,
    result: AgentRunResult,
  ]

var
  shouldRun {.volatile.} = true
  interactivePlanInterrupted {.volatile.} = false
  submitPrLock: Lock
  submitPrLockInitialized = false
  submitPrSummaries: Table[string, string]
  activeTicketEntries: Table[string, string]
  reviewActionLen = 0
  reviewActionBuffer: array[ReviewActionMaxBytes, char]
  reviewFeedbackLen = 0
  reviewFeedbackBuffer: array[ReviewFeedbackMaxBytes, char]
  ticketStartTimes*: Table[string, float]
  ticketAttemptCounts*: Table[string, int]
  ticketCodingWalls*: Table[string, float]
  ticketTestWalls*: Table[string, float]
  ticketModels*: Table[string, string]
  ticketStdoutBytes*: Table[string, int]
  sessionStats*: SessionStats
  timingsLock: Lock
  timingsLockInitialized = false
  agentResultChan: Channel[AgentCompletionResult]
  agentResultChanOpen = false
  runningAgentSlots: seq[AgentSlot]
  runningAgentThreadPtrs: seq[ptr Thread[AgentThreadArgs]]
  agentRunnerOverride*: AgentRunner
  planWorktreeLock: Lock
  planWorktreeLockInitialized = false
  rateLimitBackoffUntil*: float = 0.0
  rateLimitConsecutiveCount*: int = 0
  rateLimitConcurrencyReduction*: int = 0

proc ensureSubmitPrLockInitialized() {.gcsafe.} =
  ## Initialize the shared submit_pr lock once.
  if not submitPrLockInitialized:
    initLock(submitPrLock)
    submitPrLockInitialized = true

proc ensureTimingsLockInitialized() =
  ## Initialize the timing tables lock once.
  if not timingsLockInitialized:
    initLock(timingsLock)
    timingsLockInitialized = true

proc ensureAgentResultChanOpen() =
  ## Open the agent result channel once.
  if not agentResultChanOpen:
    agentResultChan.open()
    agentResultChanOpen = true

proc ensurePlanWorktreeLockInitialized() {.gcsafe.} =
  ## Initialize the in-process plan worktree lock once.
  if not planWorktreeLockInitialized:
    initLock(planWorktreeLock)
    planWorktreeLockInitialized = true

proc recordSubmitPrSummary*(summary: string, ticketId: string = "") {.gcsafe.} =
  ## Store the submit_pr summary for a specific ticket or the sole active ticket.
  ensureSubmitPrLockInitialized()
  {.cast(gcsafe).}:
    withLock submitPrLock:
      var id = ticketId
      if id.len == 0 and activeTicketEntries.len > 0:
        for k in activeTicketEntries.keys:
          id = k
          break
      submitPrSummaries[id] = summary

proc consumeSubmitPrSummary*(ticketId: string = ""): string {.gcsafe.} =
  ## Return and clear the submit_pr summary for a ticket or the first available.
  ensureSubmitPrLockInitialized()
  {.cast(gcsafe).}:
    withLock submitPrLock:
      if ticketId.len > 0:
        if submitPrSummaries.hasKey(ticketId):
          result = submitPrSummaries[ticketId]
          submitPrSummaries.del(ticketId)
      else:
        for k, v in submitPrSummaries:
          result = v
          submitPrSummaries.del(k)
          break

proc setActiveTicketWorktree*(worktreePath: string, ticketId: string) {.gcsafe.} =
  ## Register an active ticket worktree mapping.
  ensureSubmitPrLockInitialized()
  {.cast(gcsafe).}:
    withLock submitPrLock:
      activeTicketEntries[ticketId] = worktreePath

proc clearActiveTicketWorktree*(ticketId: string = "") {.gcsafe.} =
  ## Clear one or all active ticket worktree mappings.
  ensureSubmitPrLockInitialized()
  {.cast(gcsafe).}:
    withLock submitPrLock:
      if ticketId.len > 0:
        activeTicketEntries.del(ticketId)
      else:
        activeTicketEntries.clear()

proc getActiveTicketWorktree*(ticketId: string = ""): tuple[worktreePath: string, ticketId: string] {.gcsafe.} =
  ## Return the active worktree for a ticket or the first available entry.
  ensureSubmitPrLockInitialized()
  {.cast(gcsafe).}:
    withLock submitPrLock:
      if ticketId.len > 0:
        if activeTicketEntries.hasKey(ticketId):
          result = (worktreePath: activeTicketEntries[ticketId], ticketId: ticketId)
      elif activeTicketEntries.len > 0:
        for k, v in activeTicketEntries:
          result = (worktreePath: v, ticketId: k)
          break

proc recordReviewDecision*(action: string, feedback: string) {.gcsafe.} =
  ## Store the latest review decision reported by the review agent.
  ensureSubmitPrLockInitialized()
  withLock submitPrLock:
    let actionLen = min(action.len, ReviewActionMaxBytes)
    reviewActionLen = actionLen
    if actionLen > 0:
      copyMem(addr reviewActionBuffer[0], unsafeAddr action[0], actionLen)
    let fbLen = min(feedback.len, ReviewFeedbackMaxBytes)
    reviewFeedbackLen = fbLen
    if fbLen > 0:
      copyMem(addr reviewFeedbackBuffer[0], unsafeAddr feedback[0], fbLen)

proc consumeReviewDecision*(): tuple[action: string, feedback: string] {.gcsafe.} =
  ## Return and clear the latest review decision reported by the review agent.
  ensureSubmitPrLockInitialized()
  withLock submitPrLock:
    if reviewActionLen > 0:
      result.action = newString(reviewActionLen)
      copyMem(addr result.action[0], addr reviewActionBuffer[0], reviewActionLen)
    if reviewFeedbackLen > 0:
      result.feedback = newString(reviewFeedbackLen)
      copyMem(addr result.feedback[0], addr reviewFeedbackBuffer[0], reviewFeedbackLen)
    reviewActionLen = 0
    reviewFeedbackLen = 0

proc gitRun(dir: string, args: varargs[string]) =
  ## Run a git subcommand in dir and raise an IOError on non-zero exit.
  let argsSeq = @args
  let allArgs = @["-C", dir] & argsSeq
  let process = startProcess("git", args = allArgs, options = {poUsePath, poStdErrToStdOut})
  let output = process.outputStream.readAll()
  let rc = process.waitForExit(GitCommandTimeoutMs)
  if rc == -1 and running(process):
    process.kill()
    process.close()
    let argsStr = argsSeq.join(" ")
    raise newException(IOError, fmt"git {argsStr} timed out after {GitCommandTimeoutMs div 1000}s")
  process.close()
  if rc != 0:
    let argsStr = argsSeq.join(" ")
    raise newException(IOError, fmt"git {argsStr} failed: {output.strip()}")

proc gitCheck(dir: string, args: varargs[string]): int =
  ## Run a git subcommand in dir and return its exit code.
  let allArgs = @["-C", dir] & @args
  let process = startProcess("git", args = allArgs, options = {poUsePath, poStdErrToStdOut})
  discard process.outputStream.readAll()
  result = process.waitForExit(GitCommandTimeoutMs)
  if result == -1 and running(process):
    process.kill()
    process.close()
    let argsStr = (@args).join(" ")
    raise newException(IOError, fmt"git {argsStr} timed out after {GitCommandTimeoutMs div 1000}s")
  process.close()

proc parseWorktreeConflictPath(output: string): string =
  ## Extract a conflicting worktree path from git worktree add stderr output.
  let usedMarker = "worktree at '"
  let usedMarkerPos = output.rfind(usedMarker)
  if usedMarkerPos >= 0:
    let pathStart = usedMarkerPos + usedMarker.len
    let pathEnd = output.find('\'', pathStart)
    if pathEnd > pathStart:
      result = output[pathStart..<pathEnd].strip()
      return

  let registeredMarker = "fatal: '"
  let registeredMarkerPos = output.rfind(registeredMarker)
  if registeredMarkerPos >= 0:
    let pathStart = registeredMarkerPos + registeredMarker.len
    let missingMarker = "' is a missing but already registered worktree"
    let pathEnd = output.find(missingMarker, pathStart)
    if pathEnd > pathStart:
      result = output[pathStart..<pathEnd].strip()

proc normalizeAbsolutePath(path: string): string =
  ## Return a normalized absolute path that always uses forward slashes.
  result = absolutePath(path).replace('\\', '/')

proc repoStateKey(repoPath: string): string =
  ## Build a deterministic state key from one repository absolute path.
  let canonicalRepoPath = normalizeAbsolutePath(repoPath)
  let rawRepoName = extractFilename(canonicalRepoPath)
  let repoName = if rawRepoName.len > 0: rawRepoName else: "repo"

  var hashValue = 1469598103934665603'u64
  for ch in canonicalRepoPath:
    hashValue = (hashValue xor uint64(ord(ch))) * 1099511628211'u64
  let hashText = toLowerAscii(toHex(hashValue, 16))
  result = repoName.toLowerAscii() & "-" & hashText

proc managedRepoRootPath(repoPath: string): string =
  ## Return the deterministic managed state root path in /tmp for one repository.
  let repoKey = repoStateKey(repoPath)
  result = absolutePath(getTempDir() / ManagedStateRootDirName / repoKey)

proc managedWorktreeRootPath(repoPath: string): string =
  ## Return the deterministic managed worktree root path in /tmp for one repository.
  result = managedRepoRootPath(repoPath) / ManagedWorktreeDirName

proc managedPlanWorktreePath(repoPath: string): string =
  ## Return the deterministic plan worktree path in /tmp for one repository.
  result = managedWorktreeRootPath(repoPath) / ManagedPlanWorktreeName

proc managedMasterWorktreePath(repoPath: string): string =
  ## Return the deterministic master worktree path in /tmp for one repository.
  result = managedWorktreeRootPath(repoPath) / ManagedMasterWorktreeName

proc managedTicketWorktreeRootPath(repoPath: string): string =
  ## Return the deterministic ticket worktree root path in /tmp for one repository.
  result = managedWorktreeRootPath(repoPath) / ManagedTicketWorktreeDirName

proc managedRepoLockPath(repoPath: string): string =
  ## Return the deterministic repository lock path in /tmp for one repository.
  result = managedRepoRootPath(repoPath) / ManagedLockDirName / ManagedRepoLockName

proc isManagedWorktreePath(repoPath: string, path: string): bool =
  ## Return true when path is under this repository's managed /tmp worktree root.
  let managedRoot = normalizeAbsolutePath(managedWorktreeRootPath(repoPath))
  let normalizedPath = normalizeAbsolutePath(path)
  result = normalizedPath.startsWith(managedRoot & "/")

proc lockHolderPid(lockPath: string): int =
  ## Return lock holder PID from pid file when present and valid.
  let pidPath = lockPath / ManagedRepoLockPidFileName
  if fileExists(pidPath):
    let pidText = readFile(pidPath).strip()
    if pidText.len > 0 and pidText.allCharsInSet(Digits):
      result = parseInt(pidText)

proc lockPathIsStale(lockPath: string): bool =
  ## Return true when lock path exists but holder PID is no longer alive.
  let holderPid = lockHolderPid(lockPath)
  if holderPid <= 0:
    result = false
  else:
    let killRc = posix.kill(Pid(holderPid), 0)
    if killRc == 0:
      result = false
    else:
      let errCode = int(osLastError())
      result = errCode == ESRCH

proc tryAcquireRepoLock(lockPath: string): bool =
  ## Attempt to create one repository lock directory and return true when acquired.
  let mkdirRc = posix.mkdir(lockPath.cstring, Mode(0o700))
  if mkdirRc == 0:
    result = true
  else:
    let errCode = int(osLastError())
    if errCode == EEXIST:
      result = false
    else:
      let errNo = osLastError()
      let errText = osErrorMsg(errNo)
      raise newException(IOError, &"failed to create repo lock at {lockPath}: {errText}")

proc withRepoLock[T](repoPath: string, operation: proc(): T): T =
  ## Acquire a per-repository lock for planner and manager writes.
  let lockPath = managedRepoLockPath(repoPath)
  createDir(parentDir(lockPath))

  var acquired = tryAcquireRepoLock(lockPath)
  if not acquired and lockPathIsStale(lockPath):
    if dirExists(lockPath):
      removeDir(lockPath)
    acquired = tryAcquireRepoLock(lockPath)

  if not acquired:
    let normalizedRepoPath = normalizeAbsolutePath(repoPath)
    raise newException(IOError, &"another planner/manager is active for {normalizedRepoPath}")

  let pidPath = lockPath / ManagedRepoLockPidFileName
  let currentPid = getCurrentProcessId()
  writeFile(pidPath, &"{currentPid}\n")
  defer:
    if fileExists(pidPath):
      removeFile(pidPath)
    if dirExists(lockPath):
      removeDir(lockPath)

  result = operation()

proc recoverManagedWorktreeConflict(repoPath: string, addOutput: string): bool =
  ## Remove stale managed worktree conflicts and prune stale worktree metadata.
  let conflictPath = parseWorktreeConflictPath(addOutput)
  if conflictPath.len == 0:
    result = false
  elif not isManagedWorktreePath(repoPath, conflictPath):
    result = false
  else:
    discard gitCheck(repoPath, "worktree", "remove", "--force", conflictPath)
    discard gitCheck(repoPath, "worktree", "prune")
    if dirExists(conflictPath):
      removeDir(conflictPath)
    result = true

proc addWorktreeWithRecovery(repoPath: string, worktreePath: string, branch: string) =
  ## Add one git worktree path for one branch, recovering stale managed conflicts once.
  createDir(parentDir(worktreePath))
  if dirExists(worktreePath):
    removeDir(worktreePath)

  # Prune stale worktree entries pointing to nonexistent paths.
  discard gitCheck(repoPath, "worktree", "prune")

  var recoveredConflict = false
  while true:
    let addProcess = startProcess(
      "git",
      args = @["-C", repoPath, "worktree", "add", worktreePath, branch],
      options = {poUsePath, poStdErrToStdOut},
    )
    let addOutput = addProcess.outputStream.readAll()
    let addRc = addProcess.waitForExit()
    addProcess.close()

    if addRc == 0:
      break

    if recoveredConflict or not recoverManagedWorktreeConflict(repoPath, addOutput):
      let addOutputText = addOutput.strip()
      raise newException(
        IOError,
        &"git worktree add {worktreePath} {branch} failed: {addOutputText}",
      )
    recoveredConflict = true
    if dirExists(worktreePath):
      removeDir(worktreePath)

proc withPlanWorktreeImpl[T](repoPath: string, operation: proc(planPath: string): T): T =
  ## Open a deterministic /tmp worktree for the plan branch, then remove it.
  ## Internal: callers must hold planWorktreeLock.
  if gitCheck(repoPath, "rev-parse", "--verify", PlanBranch) != 0:
    raise newException(ValueError, "scriptorium/plan branch does not exist")

  let planWorktree = managedPlanWorktreePath(repoPath)
  addWorktreeWithRecovery(repoPath, planWorktree, PlanBranch)
  defer:
    discard gitCheck(repoPath, "worktree", "remove", "--force", planWorktree)
    discard gitCheck(repoPath, "worktree", "prune")

  result = operation(planWorktree)

proc withPlanWorktree[T](repoPath: string, operation: proc(planPath: string): T): T =
  ## Thread-safe plan worktree access for read-only operations.
  ensurePlanWorktreeLockInitialized()
  {.cast(gcsafe).}:
    acquire(planWorktreeLock)
    defer: release(planWorktreeLock)
    result = withPlanWorktreeImpl(repoPath, operation)

proc withLockedPlanWorktree[T](repoPath: string, operation: proc(planPath: string): T): T =
  ## Thread-safe plan worktree access with file-based repo lock for write operations.
  ensurePlanWorktreeLockInitialized()
  {.cast(gcsafe).}:
    acquire(planWorktreeLock)
    defer: release(planWorktreeLock)
    result = withRepoLock(repoPath, proc(): T =
      withPlanWorktreeImpl(repoPath, operation)
    )

proc loadSpecFromPlanPath(planPath: string): string =
  ## Load spec.md from an existing plan branch worktree path.
  let specPath = planPath / PlanSpecPath
  if not fileExists(specPath):
    raise newException(ValueError, "spec.md does not exist in scriptorium/plan")
  result = readFile(specPath)

proc normalizeAreaPath(rawPath: string): string =
  ## Validate and normalize a relative area path.
  let clean = rawPath.strip()
  if clean.len == 0:
    raise newException(ValueError, "area path cannot be empty")
  if clean.startsWith("/") or clean.startsWith("\\"):
    raise newException(ValueError, fmt"area path must be relative: {clean}")
  if clean.startsWith("..") or clean.contains("/../") or clean.contains("\\..\\"):
    raise newException(ValueError, fmt"area path cannot escape areas directory: {clean}")
  if not clean.toLowerAscii().endsWith(".md"):
    raise newException(ValueError, fmt"area path must be a markdown file: {clean}")
  result = clean

proc normalizeTicketSlug(rawSlug: string): string =
  ## Validate and normalize a ticket slug for filename usage.
  let clean = rawSlug.strip().toLowerAscii()
  if clean.len == 0:
    raise newException(ValueError, "ticket slug cannot be empty")

  var slug = ""
  for ch in clean:
    if ch in {'a'..'z', '0'..'9'}:
      slug.add(ch)
    elif ch in {' ', '-', '_'}:
      if slug.len > 0 and slug[^1] != '-':
        slug.add('-')

  if slug.endsWith("-"):
    slug.setLen(slug.len - 1)
  if slug.len == 0:
    raise newException(ValueError, "ticket slug must contain alphanumeric characters")
  result = slug

proc areaIdFromAreaPath(areaRelPath: string): string =
  ## Derive the area identifier from an area file path.
  result = splitFile(areaRelPath).name

proc ticketIdFromTicketPath(ticketRelPath: string): string =
  ## Extract the numeric ticket identifier prefix from a ticket path.
  let fileName = splitFile(ticketRelPath).name
  let dashPos = fileName.find('-')
  if dashPos < 1:
    raise newException(ValueError, fmt"ticket filename has no numeric prefix: {fileName}")
  let id = fileName[0..<dashPos]
  if not id.allCharsInSet(Digits):
    raise newException(ValueError, fmt"ticket filename has non-numeric prefix: {fileName}")
  result = id

proc parseAreaFromTicketContent(ticketContent: string): string =
  ## Extract the area identifier from a ticket markdown body.
  for line in ticketContent.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith(AreaFieldPrefix):
      result = trimmed[AreaFieldPrefix.len..^1].strip()
      break

proc parseDependsFromTicketContent*(ticketContent: string): seq[string] =
  ## Extract dependency ticket IDs from a ticket markdown body.
  for line in ticketContent.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith(DependsFieldPrefix):
      let raw = trimmed[DependsFieldPrefix.len..^1].strip()
      if raw.len > 0:
        for part in raw.split(","):
          let id = part.strip()
          if id.len > 0:
            result.add(id)
      break

proc parseWorktreeFromTicketContent(ticketContent: string): string =
  ## Extract the worktree path from a ticket markdown body.
  for line in ticketContent.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith(WorktreeFieldPrefix):
      let value = trimmed[WorktreeFieldPrefix.len..^1].strip()
      if value.len > 0 and value != "—" and value != "-":
        result = value
      break

proc setTicketWorktree(ticketContent: string, worktreePath: string): string =
  ## Set or append the ticket worktree metadata field.
  var lines = ticketContent.strip().splitLines()
  var updated = false
  for i in 0..<lines.len:
    if lines[i].strip().startsWith(WorktreeFieldPrefix):
      lines[i] = WorktreeFieldPrefix & " " & worktreePath
      updated = true
      break
  if not updated:
    lines.add("")
    lines.add(WorktreeFieldPrefix & " " & worktreePath)
  result = lines.join("\n") & "\n"

proc truncateTail(value: string, maxChars: int): string =
  ## Return at most maxChars from the end of value.
  if maxChars < 1:
    result = ""
  elif value.len <= maxChars:
    result = value
  else:
    result = value[(value.len - maxChars)..^1]

proc clipPlanStreamText(value: string): string =
  ## Clip one stream message for concise interactive status rendering.
  let normalized = value.replace('\n', ' ').replace('\r', ' ').strip()
  if normalized.len <= PlanStreamPreviewChars:
    result = normalized
  elif PlanStreamPreviewChars > 3:
    result = normalized[0..<(PlanStreamPreviewChars - 3)] & "..."
  else:
    result = normalized

proc formatPlanStreamEvent(event: AgentStreamEvent): string =
  ## Format one agent stream event for interactive planning output.
  let text = clipPlanStreamText(event.text)
  case event.kind
  of agentEventHeartbeat:
    result = "[thinking] still working..."
  of agentEventReasoning:
    if text.len > 0:
      result = "[thinking] " & text
    else:
      result = "[thinking]"
  of agentEventTool:
    if text.len > 0:
      result = "[tool] " & text
    else:
      result = "[tool]"
  of agentEventStatus:
    if text.len > 0:
      result = "[status] " & text
    else:
      result = ""
  of agentEventMessage:
    result = ""

proc buildCodingAgentPrompt(repoPath: string, worktreePath: string, ticketRelPath: string, ticketContent: string): string =
  ## Build the coding-agent prompt from ticket context.
  result = renderPromptTemplate(
    CodingAgentTemplate,
    [
      (name: "PROJECT_REPO_PATH", value: repoPath),
      (name: "WORKTREE_PATH", value: worktreePath),
      (name: "TICKET_PATH", value: ticketRelPath),
      (name: "TICKET_CONTENT", value: ticketContent.strip()),
    ],
  )

proc formatDuration*(seconds: float): string =
  ## Format a duration in seconds as a human-readable string like 1h23m or 3m12s.
  let totalSecs = seconds.int
  if totalSecs < 60:
    result = $totalSecs & "s"
  elif totalSecs < 3600:
    let mins = totalSecs div 60
    let secs = totalSecs mod 60
    result = $mins & "m" & $secs & "s"
  else:
    let hours = totalSecs div 3600
    let mins = (totalSecs mod 3600) div 60
    result = $hours & "h" & $mins & "m"

proc buildStallContinuationPrompt(initialPrompt: string, ticketContent: string, ticketId: string, attempt: int, testExitCode: int, testOutput: string): string =
  ## Build a continuation prompt for a coding agent that stalled without calling submit_pr.
  ## Includes test results: pass/fail status and output from `make test`.
  let testSection =
    if testExitCode == 0:
      "## Test Results\n\nTests are passing (`make test` exited 0). Continue working on the ticket and call `submit_pr` when done."
    else:
      let truncated = truncateTail(testOutput.strip(), StallTestOutputMaxBytes)
      "## Test Results\n\nTests are FAILING (`make test` exited " & $testExitCode & "). Fix the failing tests before submitting.\n\n```\n" & truncated & "\n```"
  result = initialPrompt.strip() & "\n\n" &
    fmt"This is stall retry attempt {attempt} for ticket {ticketId}. " &
    "The previous attempt exited cleanly without calling the `submit_pr` MCP tool.\n\n" &
    "Ticket content:\n\n" & ticketContent.strip() & "\n\n" &
    StallContinuationText & "\n\n" &
    testSection

proc buildReviewAgentPrompt*(ticketContent: string, diffContent: string, areaContent: string, submitSummary: string): string =
  ## Build the review agent prompt from ticket, diff, area, and summary context.
  result = renderPromptTemplate(
    ReviewAgentTemplate,
    [
      (name: "TICKET_CONTENT", value: ticketContent.strip()),
      (name: "DIFF_CONTENT", value: diffContent.strip()),
      (name: "AREA_CONTENT", value: areaContent.strip()),
      (name: "SUBMIT_SUMMARY", value: submitSummary.strip()),
    ],
  )

proc buildArchitectAreasPrompt(repoPath: string, planPath: string, spec: string): string =
  ## Build the architect prompt that writes area files directly into areas/.
  result = renderPromptTemplate(
    ArchitectAreasTemplate,
    [
      (name: "PROJECT_REPO_PATH", value: repoPath),
      (name: "WORKTREE_PATH", value: planPath),
      (name: "CURRENT_SPEC", value: spec.strip()),
    ],
  )

proc buildManagerTicketsBatchPrompt(repoPath: string, planPath: string,
    areas: seq[tuple[relPath: string, content: string]], nextId: int): string =
  ## Build a batch manager prompt covering all areas in a single session.
  var areasBlock = ""
  for area in areas:
    let areaId = areaIdFromAreaPath(area.relPath)
    areasBlock.add(&"### Area: {areaId}\nPath: {area.relPath}\nContent:\n{area.content.strip()}\n\n")
  let startIdText = &"{nextId:04d}"
  result = renderPromptTemplate(
    ManagerTicketsBatchTemplate,
    [
      (name: "PROJECT_REPO_PATH", value: repoPath),
      (name: "WORKTREE_PATH", value: planPath),
      (name: "START_ID", value: startIdText),
      (name: "AREA_FIELD_PREFIX", value: AreaFieldPrefix),
      (name: "AREAS_BLOCK", value: areasBlock.strip()),
    ],
  )

proc formatAgentRunNote(model: string, runResult: AgentRunResult): string =
  ## Format a markdown note summarizing one coding-agent run.
  let messagePreview = truncateTail(runResult.lastMessage.strip(), AgentMessagePreviewChars)
  let stdoutPreview = truncateTail(runResult.stdout.strip(), AgentStdoutPreviewChars)
  result =
    "## Agent Run\n" &
    fmt"- Model: {model}\n" &
    fmt"- Backend: {runResult.backend}\n" &
    fmt"- Exit Code: {runResult.exitCode}\n" &
    fmt"- Attempt: {runResult.attempt}\n" &
    fmt"- Attempt Count: {runResult.attemptCount}\n" &
    fmt"- Timeout: {runResult.timeoutKind}\n" &
    fmt"- Log File: {runResult.logFile}\n" &
    fmt"- Last Message File: {runResult.lastMessageFile}\n"

  if messagePreview.len > 0:
    result &=
      "\n### Agent Last Message\n" &
      "```text\n" &
      messagePreview & "\n" &
      "```\n"

  if stdoutPreview.len > 0:
    result &=
      "\n### Agent Stdout Tail\n" &
      "```text\n" &
      stdoutPreview & "\n" &
      "```\n"

proc appendAgentRunNote(ticketContent: string, model: string, runResult: AgentRunResult): string =
  ## Append a formatted coding-agent run note to a ticket markdown document.
  let base = ticketContent.strip()
  let note = formatAgentRunNote(model, runResult).strip()
  result = base & "\n\n" & note & "\n"

proc formatMetricsNote*(ticketId: string, outcome: string, failureReason: string): string =
  ## Format a structured metrics section for a completed ticket.
  let wallTimeSeconds = block:
    let startTime = ticketStartTimes.getOrDefault(ticketId, 0.0)
    if startTime > 0.0: int(epochTime() - startTime) else: 0
  let codingWallSeconds = int(ticketCodingWalls.getOrDefault(ticketId, 0.0))
  let testWallSeconds = int(ticketTestWalls.getOrDefault(ticketId, 0.0))
  let attemptCount = ticketAttemptCounts.getOrDefault(ticketId, 0)
  let model = ticketModels.getOrDefault(ticketId, "unknown")
  let stdoutBytes = ticketStdoutBytes.getOrDefault(ticketId, 0)
  result =
    "## Metrics\n" &
    &"- wall_time_seconds: {wallTimeSeconds}\n" &
    &"- coding_wall_seconds: {codingWallSeconds}\n" &
    &"- test_wall_seconds: {testWallSeconds}\n" &
    &"- attempt_count: {attemptCount}\n" &
    &"- outcome: {outcome}\n" &
    &"- failure_reason: {failureReason}\n" &
    &"- model: {model}\n" &
    &"- stdout_bytes: {stdoutBytes}\n"

proc getSessionStdoutBytes*(): int =
  ## Sum all ticketStdoutBytes values to get the session-level total.
  for bytes in ticketStdoutBytes.values:
    result += bytes

proc isTokenBudgetExceeded*(tokenBudgetMB: int): bool =
  ## Check if cumulative stdout bytes exceed the token budget. Returns false when budget is 0 (unlimited).
  if tokenBudgetMB <= 0:
    return false
  let budgetBytes = tokenBudgetMB * 1024 * 1024
  let usedBytes = getSessionStdoutBytes()
  if usedBytes >= budgetBytes:
    let usedMB = usedBytes div (1024 * 1024)
    logInfo(&"resource limit: token budget exhausted ({usedMB}MB/{tokenBudgetMB}MB), pausing new assignments")
    return true
  return false

proc isRateLimited*(output: string): bool =
  ## Check if agent output contains rate limit indicators (HTTP 429 or equivalent).
  let lower = output.toLowerAscii()
  if "429" in lower and ("rate" in lower or "too many" in lower or "limit" in lower):
    return true
  if "rate limit" in lower or "rate_limit" in lower or "ratelimit" in lower:
    return true
  if "too many requests" in lower:
    return true
  return false

proc rateLimitBackoffSeconds*(): float =
  ## Calculate the current exponential backoff duration based on consecutive rate limit count.
  if rateLimitConsecutiveCount <= 0:
    return 0.0
  let exponent = rateLimitConsecutiveCount - 1
  let backoff = RateLimitBaseBackoffSeconds * pow(RateLimitBackoffMultiplier, exponent.float)
  result = min(backoff, RateLimitMaxBackoffSeconds)

proc recordRateLimit*(ticketId: string) =
  ## Record a rate limit event: increment counter, set backoff expiry, reduce concurrency by 1.
  rateLimitConsecutiveCount += 1
  let backoffSecs = rateLimitBackoffSeconds()
  rateLimitBackoffUntil = epochTime() + backoffSecs
  rateLimitConcurrencyReduction = rateLimitConsecutiveCount
  let backoffInt = int(backoffSecs)
  logInfo(&"resource limit: rate limited (ticket {ticketId}, backing off {backoffInt}s)")

proc isRateLimitBackoffActive*(): bool =
  ## Check if rate limit backoff is currently active. Restores concurrency when backoff expires.
  if rateLimitBackoffUntil <= 0.0:
    return false
  if epochTime() >= rateLimitBackoffUntil:
    rateLimitBackoffUntil = 0.0
    rateLimitConsecutiveCount = 0
    rateLimitConcurrencyReduction = 0
    return false
  return true

proc effectiveMaxAgents*(maxAgents: int): int =
  ## Return the effective max agents after applying rate limit concurrency reduction.
  result = max(1, maxAgents - rateLimitConcurrencyReduction)

proc resetRateLimitState*() =
  ## Reset all rate limit backpressure state.
  rateLimitBackoffUntil = 0.0
  rateLimitConsecutiveCount = 0
  rateLimitConcurrencyReduction = 0

proc appendMetricsNote*(ticketContent: string, ticketId: string, outcome: string, failureReason: string): string =
  ## Append a structured metrics section to a ticket markdown document.
  let base = ticketContent.strip()
  let note = formatMetricsNote(ticketId, outcome, failureReason).strip()
  result = base & "\n\n" & note & "\n"

type
  TicketPrediction* = object
    difficulty*: string
    durationMinutes*: int
    reasoning*: string

const
  ValidDifficulties = ["trivial", "easy", "medium", "hard", "complex"]

proc parsePredictionResponse*(response: string): TicketPrediction =
  ## Parse a JSON prediction response from the model into a TicketPrediction.
  let trimmed = response.strip()
  # Find JSON object in response (skip any surrounding text or markdown fences).
  var jsonStart = trimmed.find('{')
  var jsonEnd = trimmed.rfind('}')
  if jsonStart < 0 or jsonEnd < 0 or jsonEnd <= jsonStart:
    raise newException(ValueError, "no JSON object found in prediction response")
  let jsonStr = trimmed[jsonStart..jsonEnd]
  let node = parseJson(jsonStr)
  let difficulty = node.getOrDefault("predicted_difficulty").getStr("")
  if difficulty notin ValidDifficulties:
    raise newException(ValueError, "invalid predicted_difficulty: " & difficulty)
  let durationMinutes = node.getOrDefault("predicted_duration_minutes").getInt(0)
  let reasoning = node.getOrDefault("reasoning").getStr("")
  result = TicketPrediction(
    difficulty: difficulty,
    durationMinutes: durationMinutes,
    reasoning: reasoning,
  )

proc formatPredictionNote*(prediction: TicketPrediction): string =
  ## Format a prediction section for appending to ticket markdown.
  result =
    "## Prediction\n" &
    &"- predicted_difficulty: {prediction.difficulty}\n" &
    &"- predicted_duration_minutes: {prediction.durationMinutes}\n" &
    &"- reasoning: {prediction.reasoning}\n"

proc appendPredictionNote*(ticketContent: string, prediction: TicketPrediction): string =
  ## Append a prediction section to a ticket markdown document.
  let base = ticketContent.strip()
  let note = formatPredictionNote(prediction).strip()
  result = base & "\n\n" & note & "\n"

proc buildPredictionPrompt*(ticketContent: string, areaContent: string, specSummary: string): string =
  ## Build the prediction prompt from ticket, area, and spec context.
  result = renderPromptTemplate(
    TicketPredictionTemplate,
    [
      (name: "TICKET_CONTENT", value: ticketContent.strip()),
      (name: "AREA_CONTENT", value: areaContent.strip()),
      (name: "SPEC_SUMMARY", value: specSummary.strip()),
    ],
  )

proc predictTicketDifficulty*(
  repoPath: string,
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
    areaContent = withPlanWorktree(repoPath, proc(planPath: string): string =
      let areaPath = planPath / PlanAreasDir / areaId & ".md"
      if fileExists(areaPath):
        result = readFile(areaPath)
    )

  # Gather spec summary.
  let specSummary = withPlanWorktree(repoPath, proc(planPath: string): string =
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

proc cleanupTicketTimings*(ticketId: string) =
  ## Remove all per-ticket timing and metrics state for a completed ticket.
  ticketStartTimes.del(ticketId)
  ticketAttemptCounts.del(ticketId)
  ticketCodingWalls.del(ticketId)
  ticketTestWalls.del(ticketId)
  ticketModels.del(ticketId)
  ticketStdoutBytes.del(ticketId)

proc parsePredictionFromContent*(content: string): tuple[found: bool, difficulty: string, durationMinutes: int] =
  ## Extract predicted difficulty and duration from a ticket's Prediction section.
  let marker = "## Prediction"
  let idx = content.find(marker)
  if idx < 0:
    return (found: false, difficulty: "", durationMinutes: 0)
  let section = content[idx .. ^1]
  var difficulty = ""
  var durationMinutes = 0
  for line in section.splitLines():
    if line.startsWith("## ") and line != marker:
      break
    if line.startsWith("- predicted_difficulty: "):
      difficulty = line["- predicted_difficulty: ".len .. ^1].strip()
    elif line.startsWith("- predicted_duration_minutes: "):
      let valStr = line["- predicted_duration_minutes: ".len .. ^1].strip()
      durationMinutes = parseInt(valStr)
  if difficulty.len == 0:
    return (found: false, difficulty: "", durationMinutes: 0)
  result = (found: true, difficulty: difficulty, durationMinutes: durationMinutes)

proc classifyActualDifficulty*(attemptCount: int, outcome: string, wallTimeSeconds: int): string =
  ## Classify actual difficulty based on attempt count, outcome, and wall time.
  if outcome == "parked":
    return "complex"
  if outcome == "reopened":
    if attemptCount >= 3:
      return "complex"
    return "hard"
  # outcome == "done"
  if attemptCount == 1 and wallTimeSeconds < 300:
    return "trivial"
  if attemptCount == 1 and wallTimeSeconds < 900:
    return "easy"
  if attemptCount == 1:
    return "medium"
  if attemptCount == 2:
    return "hard"
  return "complex"

proc compareDifficulty*(predicted: string, actual: string): string =
  ## Compare predicted vs actual difficulty and return accuracy label.
  let levels = @["trivial", "easy", "medium", "hard", "complex"]
  let predIdx = levels.find(predicted)
  let actIdx = levels.find(actual)
  if predIdx < 0 or actIdx < 0:
    return "accurate"
  if predIdx == actIdx:
    return "accurate"
  if predIdx < actIdx:
    return "underestimated"
  return "overestimated"

proc formatPostAnalysisNote*(actualDifficulty: string, predictionAccuracy: string, briefSummary: string): string =
  ## Format a post-analysis section for appending to ticket markdown.
  result =
    "## Post-Analysis\n" &
    &"- actual_difficulty: {actualDifficulty}\n" &
    &"- prediction_accuracy: {predictionAccuracy}\n" &
    &"- brief_summary: {briefSummary}\n"

proc appendPostAnalysisNote*(ticketContent: string, actualDifficulty: string, predictionAccuracy: string, briefSummary: string): string =
  ## Append a post-analysis section to a ticket markdown document.
  let base = ticketContent.strip()
  let note = formatPostAnalysisNote(actualDifficulty, predictionAccuracy, briefSummary).strip()
  result = base & "\n\n" & note & "\n"

proc runPostAnalysis*(ticketContent: string, ticketId: string, outcome: string, attemptCount: int, wallTimeSeconds: int): string =
  ## Run post-analysis comparing predicted vs actual metrics. Returns updated content.
  ## If no prediction section exists, returns the original content unchanged.
  let prediction = parsePredictionFromContent(ticketContent)
  if not prediction.found:
    logInfo(&"ticket {ticketId}: post-analysis skipped (no prediction section)")
    return ticketContent
  let actualDifficulty = classifyActualDifficulty(attemptCount, outcome, wallTimeSeconds)
  let predictionAccuracy = compareDifficulty(prediction.difficulty, actualDifficulty)
  let wallDuration = formatDuration(float(wallTimeSeconds))
  let briefSummary = &"Predicted {prediction.difficulty}, actual was {actualDifficulty} with {attemptCount} attempt(s) in {wallDuration}."
  logInfo(&"ticket {ticketId}: post-analysis: predicted={prediction.difficulty} actual={actualDifficulty} accuracy={predictionAccuracy} wall={wallDuration}")
  result = appendPostAnalysisNote(ticketContent, actualDifficulty, predictionAccuracy, briefSummary)

proc branchNameForTicket(ticketRelPath: string): string =
  ## Build a deterministic branch name for a ticket.
  result = TicketBranchPrefix & ticketIdFromTicketPath(ticketRelPath)

proc buildPlanScopePrompt(repoPath: string, planPath: string): string =
  ## Build shared planning prompt context with read and write scope.
  result = renderPromptTemplate(
    PlanScopeTemplate,
    [
      (name: "PROJECT_REPO_PATH", value: repoPath),
      (name: "WORKTREE_PATH", value: planPath),
    ],
  )

proc buildArchitectPlanPrompt(repoPath: string, planPath: string, userPrompt: string, currentSpec: string): string =
  ## Build the one-shot architect prompt that edits spec.md in place.
  result = renderPromptTemplate(
    ArchitectPlanOneShotTemplate,
    [
      (name: "PLAN_SCOPE", value: buildPlanScopePrompt(repoPath, planPath).strip()),
      (name: "USER_REQUEST", value: userPrompt.strip()),
      (name: "CURRENT_SPEC", value: currentSpec.strip()),
    ],
  )

proc runPlanArchitectRequest(
  runner: AgentRunner,
  planPath: string,
  agentCfg: AgentConfig,
  prompt: string,
  ticketId: string,
  onEvent: AgentEventHandler = nil,
  heartbeatIntervalMs: int = 0,
): AgentRunResult =
  ## Run one architect planning pass with shared harness settings.
  if runner.isNil:
    raise newException(ValueError, "agent runner is required")
  result = runner(AgentRunRequest(
    prompt: prompt,
    workingDir: planPath,
    harness: agentCfg.harness,
    model: agentCfg.model,
    reasoningEffort: agentCfg.reasoningEffort,
    ticketId: ticketId,
    attempt: DefaultAgentAttempt,
    skipGitRepoCheck: true,
    logRoot: getTempDir() / PlanLogRoot,
    noOutputTimeoutMs: PlanNoOutputTimeoutMs,
    hardTimeoutMs: PlanHardTimeoutMs,
    heartbeatIntervalMs: heartbeatIntervalMs,
    maxAttempts: PlanDefaultMaxAttempts,
    onEvent: onEvent,
  ))

proc planAgentLogRoot(ticketId: string): string =
  ## Return a temp log root for one plan-branch agent run.
  let cleanTicketId = ticketId.strip()
  if cleanTicketId.len > 0:
    result = getTempDir() / PlanLogRoot / cleanTicketId
  else:
    result = getTempDir() / PlanLogRoot

proc listMarkdownFiles(basePath: string): seq[string] =
  ## Collect markdown files recursively and return sorted absolute paths.
  if not dirExists(basePath):
    result = @[]
  else:
    for filePath in walkDirRec(basePath):
      if filePath.toLowerAscii().endsWith(".md"):
        result.add(filePath)
    result.sort()

proc runCommandCapture(workingDir: string, command: string, args: seq[string], timeoutMs: int = QualityCheckTimeoutMs): tuple[exitCode: int, output: string] =
  ## Run a process and return combined stdout/stderr with its exit code.
  let process = startProcess(
    command,
    workingDir = workingDir,
    args = args,
    options = {poUsePath, poStdErrToStdOut},
  )
  let output = process.outputStream.readAll()
  let exitCode = process.waitForExit(timeoutMs)
  if exitCode == -1 and running(process):
    process.kill()
    process.close()
    let cmdStr = command & " " & args.join(" ")
    raise newException(IOError, fmt"{cmdStr} timed out after {timeoutMs div 1000}s")
  process.close()
  result = (exitCode: exitCode, output: output)

proc normalizeRelativeWritePath(rawPath: string): string =
  ## Validate and normalize one relative path for write guard checks.
  let clean = rawPath.strip().replace('\\', '/')
  if clean.len == 0:
    raise newException(ValueError, "write guard path cannot be empty")
  if clean.startsWith("/") or (clean.len >= 2 and clean[1] == ':'):
    raise newException(ValueError, fmt"write guard path must be relative: {clean}")

  var parts: seq[string] = @[]
  for part in clean.split('/'):
    if part.len == 0 or part == ".":
      continue
    if part == "..":
      raise newException(ValueError, fmt"write guard path cannot escape worktree: {clean}")
    parts.add(part)

  if parts.len == 0:
    raise newException(ValueError, fmt"write guard path is invalid: {clean}")
  result = parts.join("/")

proc collectGitPathOutput(gitPath: string, args: seq[string]): seq[string] =
  ## Run one git command that emits relative paths and return non-empty lines.
  let commandResult = runCommandCapture(gitPath, "git", args)
  if commandResult.exitCode != 0:
    let argsText = args.join(" ")
    raise newException(IOError, fmt"git {argsText} failed while checking write guards: {commandResult.output.strip()}")
  for line in commandResult.output.splitLines():
    let trimmed = line.strip()
    if trimmed.len > 0:
      result.add(trimmed)

proc listModifiedPathsInGitPath(gitPath: string): seq[string] =
  ## Return modified and untracked relative paths in one git worktree path.
  var seen = initHashSet[string]()
  let commands = @[
    @["diff", "--name-only", "--relative"],
    @["diff", "--cached", "--name-only", "--relative"],
    @["ls-files", "--others", "--exclude-standard"],
  ]

  for args in commands:
    for rawPath in collectGitPathOutput(gitPath, args):
      let normalized = normalizeRelativeWritePath(rawPath)
      if not seen.contains(normalized):
        seen.incl(normalized)
        result.add(normalized)
  result.sort()

proc listModifiedPathsInPlanPath(planPath: string): seq[string] =
  ## Return modified and untracked relative paths in the plan worktree.
  result = listModifiedPathsInGitPath(planPath)

proc enforceWriteAllowlist(planPath: string, allowedPaths: openArray[string], scopeName: string) =
  ## Fail when modified paths are outside the provided relative-path allowlist.
  if allowedPaths.len == 0:
    raise newException(ValueError, "write allowlist cannot be empty")

  var allowedSet = initHashSet[string]()
  var allowedList: seq[string] = @[]
  for path in allowedPaths:
    let normalized = normalizeRelativeWritePath(path)
    if not allowedSet.contains(normalized):
      allowedSet.incl(normalized)
      allowedList.add(normalized)
  allowedList.sort()

  var disallowed: seq[string] = @[]
  for path in listModifiedPathsInPlanPath(planPath):
    if not allowedSet.contains(path):
      disallowed.add(path)

  if disallowed.len > 0:
    let disallowedText = disallowed.join(", ")
    let allowedText = allowedList.join(", ")
    raise newException(
      ValueError,
      fmt"{scopeName} modified out-of-scope files: {disallowedText}. Allowed files: {allowedText}.",
    )

proc enforceNoWrites(planPath: string, scopeName: string) =
  ## Fail when any files were modified in the plan worktree.
  let modified = listModifiedPathsInPlanPath(planPath)
  if modified.len > 0:
    let modifiedText = modified.join(", ")
    raise newException(
      ValueError,
      fmt"{scopeName} modified files in read-only mode: {modifiedText}.",
    )

proc isPathInAllowedPrefix(path: string, prefix: string): bool =
  ## Return true when one relative path is under one normalized allowlist prefix.
  result = path == prefix or path.startsWith(prefix & "/")

proc enforceWritePrefixAllowlist(planPath: string, allowedPrefixes: openArray[string], scopeName: string) =
  ## Fail when modified paths are outside the provided relative-path prefix allowlist.
  if allowedPrefixes.len == 0:
    raise newException(ValueError, "write prefix allowlist cannot be empty")

  var prefixSet = initHashSet[string]()
  var prefixList: seq[string] = @[]
  for prefix in allowedPrefixes:
    let normalized = normalizeRelativeWritePath(prefix)
    if not prefixSet.contains(normalized):
      prefixSet.incl(normalized)
      prefixList.add(normalized)
  prefixList.sort()

  var disallowed: seq[string] = @[]
  for path in listModifiedPathsInPlanPath(planPath):
    var allowed = false
    for prefix in prefixList:
      if isPathInAllowedPrefix(path, prefix):
        allowed = true
        break
    if not allowed:
      disallowed.add(path)

  if disallowed.len > 0:
    let disallowedText = disallowed.join(", ")
    let allowedText = prefixList.join(", ")
    raise newException(
      ValueError,
      fmt"{scopeName} modified out-of-scope files: {disallowedText}. Allowed prefixes: {allowedText}.",
    )

proc pathFingerprintInGitPath(gitPath: string, relPath: string): string =
  ## Return a stable fingerprint for one relative path in one git worktree path.
  let absPath = gitPath / relPath
  if fileExists(absPath):
    let hashResult = runCommandCapture(gitPath, "git", @["hash-object", "--", relPath])
    if hashResult.exitCode != 0:
      raise newException(IOError, fmt"git hash-object failed for {relPath}: {hashResult.output.strip()}")
    result = hashResult.output.strip()
  elif dirExists(absPath):
    result = "<dir>"
  else:
    result = "<missing>"

proc snapshotDirtyStateInGitPath(gitPath: string): Table[string, string] =
  ## Snapshot dirty tracked and untracked paths with content fingerprints.
  result = initTable[string, string]()
  for path in listModifiedPathsInGitPath(gitPath):
    result[path] = pathFingerprintInGitPath(gitPath, path)

proc diffDirtyStatePaths(beforeState: Table[string, string], afterState: Table[string, string]): seq[string] =
  ## Return dirty paths whose fingerprint changed between two snapshots.
  var changedSet = initHashSet[string]()

  for path, beforeFingerprint in beforeState.pairs():
    if not afterState.hasKey(path) or afterState[path] != beforeFingerprint:
      changedSet.incl(path)

  for path in afterState.keys():
    if not beforeState.hasKey(path):
      changedSet.incl(path)

  for path in changedSet:
    result.add(path)
  result.sort()

proc enforceGitPathUnchanged(gitPath: string, beforeState: Table[string, string], scopeName: string) =
  ## Fail when one git worktree path dirty-state snapshot changed.
  let afterState = snapshotDirtyStateInGitPath(gitPath)
  let changedPaths = diffDirtyStatePaths(beforeState, afterState)
  if changedPaths.len > 0:
    let changedText = changedPaths.join(", ")
    raise newException(
      ValueError,
      fmt"{scopeName} modified repository files outside the plan worktree: {changedText}.",
    )

proc ensureUniqueTicketStateInPlanPath(planPath: string) =
  ## Ensure each ticket markdown filename exists in exactly one state directory.
  var seen = initHashSet[string]()
  for stateDir in [PlanTicketsOpenDir, PlanTicketsInProgressDir, PlanTicketsDoneDir, PlanTicketsStuckDir]:
    for ticketPath in listMarkdownFiles(planPath / stateDir):
      let fileName = extractFilename(ticketPath)
      if seen.contains(fileName):
        raise newException(ValueError, fmt"ticket exists in multiple state directories: {fileName}")
      seen.incl(fileName)

proc hasRunnableSpecInPlanPath(planPath: string): bool =
  ## Return true when spec.md exists and is not blank or the init placeholder.
  let specPath = planPath / PlanSpecPath
  if not fileExists(specPath):
    return false

  let specBody = readFile(specPath).strip()
  if specBody.len == 0:
    return false
  result = specBody != PlanSpecPlaceholder.strip()

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

proc runWorktreeMakeTest(worktreePath: string): tuple[exitCode: int, output: string] =
  ## Run `make test` in the agent worktree and return exit code and combined output.
  result = runCommandCapture(worktreePath, "make", @["test"], MakeTestTimeoutMs)

proc runRequiredQualityChecks(workingDir: string): tuple[exitCode: int, output: string, failedTarget: string] =
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

proc withMasterWorktree[T](repoPath: string, operation: proc(masterPath: string): T): T =
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

proc ensureMergeQueueInitializedInPlanPath(planPath: string): bool =
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

proc queueItemToMarkdown(item: MergeQueueItem): string =
  ## Convert one merge queue item into markdown.
  result =
    "# Merge Queue Item\n\n" &
    "**Ticket:** " & item.ticketPath & "\n" &
    "**Ticket ID:** " & item.ticketId & "\n" &
    "**Branch:** " & item.branch & "\n" &
    "**Worktree:** " & item.worktree & "\n" &
    "**Summary:** " & item.summary & "\n"

proc parseQueueField(content: string, prefix: string): string =
  ## Parse one single-line markdown field from queue item content.
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith(prefix):
      result = trimmed[prefix.len..^1].strip()
      break

proc parseMergeQueueItem(pendingPath: string, content: string): MergeQueueItem =
  ## Parse one merge queue item from markdown.
  result = MergeQueueItem(
    pendingPath: pendingPath,
    ticketPath: parseQueueField(content, "**Ticket:**"),
    ticketId: parseQueueField(content, "**Ticket ID:**"),
    branch: parseQueueField(content, "**Branch:**"),
    worktree: parseQueueField(content, "**Worktree:**"),
    summary: parseQueueField(content, "**Summary:**"),
  )
  if result.ticketPath.len == 0 or result.ticketId.len == 0 or result.branch.len == 0 or result.worktree.len == 0:
    raise newException(ValueError, fmt"invalid merge queue item: {pendingPath}")

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

proc listMergeQueueItems(planPath: string): seq[MergeQueueItem] =
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

proc listActiveTicketWorktreesInPlanPath(planPath: string): seq[ActiveTicketWorktree] =
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

proc formatMergeFailureNote(summary: string, mergeOutput: string, checkOutput: string, failedStep: string): string =
  ## Format a ticket note for failed merge queue processing.
  let mergePreview = truncateTail(mergeOutput.strip(), MergeQueueOutputPreviewChars)
  let checkPreview = truncateTail(checkOutput.strip(), MergeQueueOutputPreviewChars)
  result =
    "## Merge Queue Failure\n" &
    fmt"- Summary: {summary}\n"
  if failedStep.len > 0:
    result &= fmt"- Failed gate: {failedStep}\n"
  if mergePreview.len > 0:
    result &=
      "\n### Merge Output\n" &
      "```text\n" &
      mergePreview & "\n" &
      "```\n"
  if checkPreview.len > 0:
    result &=
      "\n### Quality Check Output\n" &
      "```text\n" &
      checkPreview & "\n" &
      "```\n"

proc formatMergeSuccessNote(summary: string, checkOutput: string): string =
  ## Format a ticket note for successful merge queue processing.
  let checkPreview = truncateTail(checkOutput.strip(), MergeQueueOutputPreviewChars)
  result =
    "## Merge Queue Success\n" &
    fmt"- Summary: {summary}\n"
  if checkPreview.len > 0:
    result &=
      "\n### Quality Check Output\n" &
      "```text\n" &
      checkPreview & "\n" &
      "```\n"

proc computeContentHash(content: string): string =
  ## SHA-1 hex digest of content for change detection.
  result = $secureHash(content)

proc readSpecHashMarker(planPath: string): string =
  ## Read stored spec hash, or "" if missing.
  let path = planPath / SpecHashMarkerPath
  if fileExists(path):
    result = readFile(path).strip()
  else:
    result = ""

proc writeSpecHashMarker(planPath: string) =
  ## Write SHA-1 of current spec.md to areas/.spec-hash.
  let spec = loadSpecFromPlanPath(planPath)
  let hash = computeContentHash(spec)
  createDir(parentDir(planPath / SpecHashMarkerPath))
  writeFile(planPath / SpecHashMarkerPath, hash & "\n")

proc readAreaHashes(planPath: string): Table[string, string] =
  ## Read area-id:hash pairs from tickets/.area-hashes.
  result = initTable[string, string]()
  let path = planPath / AreaHashesPath
  if fileExists(path):
    for line in readFile(path).splitLines():
      let stripped = line.strip()
      if stripped.len == 0:
        continue
      let colonPos = stripped.find(':')
      if colonPos > 0:
        let areaId = stripped[0..<colonPos]
        let hash = stripped[colonPos + 1..^1]
        result[areaId] = hash

proc writeAreaHashes(planPath: string, hashes: Table[string, string]) =
  ## Write area-id:hash pairs to tickets/.area-hashes.
  var lines: seq[string] = @[]
  for areaId, hash in hashes:
    lines.add(areaId & ":" & hash)
  lines.sort()
  createDir(parentDir(planPath / AreaHashesPath))
  writeFile(planPath / AreaHashesPath, lines.join("\n") & "\n")

proc computeAllAreaHashes(planPath: string): Table[string, string] =
  ## Compute content hashes for all area markdown files.
  result = initTable[string, string]()
  for areaPath in listMarkdownFiles(planPath / PlanAreasDir):
    let relativeAreaPath = relativePath(areaPath, planPath).replace('\\', '/')
    let areaId = areaIdFromAreaPath(relativeAreaPath)
    result[areaId] = computeContentHash(readFile(areaPath))

proc collectActiveTicketAreas(planPath: string): HashSet[string] =
  ## Collect area identifiers that have open, in-progress, or done tickets.
  result = initHashSet[string]()
  for stateDir in [PlanTicketsOpenDir, PlanTicketsInProgressDir, PlanTicketsDoneDir, PlanTicketsStuckDir]:
    for ticketPath in listMarkdownFiles(planPath / stateDir):
      let areaId = parseAreaFromTicketContent(readFile(ticketPath))
      if areaId.len > 0:
        result.incl(areaId)

proc collectOpenAndInProgressAreas(planPath: string): HashSet[string] =
  ## Collect area identifiers that have open or in-progress tickets (blocks concurrent work).
  result = initHashSet[string]()
  for stateDir in [PlanTicketsOpenDir, PlanTicketsInProgressDir]:
    for ticketPath in listMarkdownFiles(planPath / stateDir):
      let areaId = parseAreaFromTicketContent(readFile(ticketPath))
      if areaId.len > 0:
        result.incl(areaId)

proc areasNeedingTicketsInPlanPath(planPath: string): seq[string] =
  ## Return area files eligible for ticket generation.
  ## Uses hash-based comparison when area hashes file exists; falls back to
  ## legacy behavior (suppress areas with any ticket) when no hashes file.
  let hasAreaHashes = fileExists(planPath / AreaHashesPath)

  if not hasAreaHashes:
    # Legacy fallback: suppress areas with any ticket (open, in-progress, done, stuck)
    let activeAreas = collectActiveTicketAreas(planPath)
    for areaPath in listMarkdownFiles(planPath / PlanAreasDir):
      let relativeAreaPath = relativePath(areaPath, planPath).replace('\\', '/')
      let areaId = areaIdFromAreaPath(relativeAreaPath)
      if not activeAreas.contains(areaId):
        result.add(relativeAreaPath)
  else:
    # Hash-based: skip areas with open/in-progress work, include changed content
    let storedHashes = readAreaHashes(planPath)
    let openOrInProgress = collectOpenAndInProgressAreas(planPath)
    for areaPath in listMarkdownFiles(planPath / PlanAreasDir):
      let relativeAreaPath = relativePath(areaPath, planPath).replace('\\', '/')
      let areaId = areaIdFromAreaPath(relativeAreaPath)
      if openOrInProgress.contains(areaId):
        continue
      let currentHash = computeContentHash(readFile(areaPath))
      let storedHash = storedHashes.getOrDefault(areaId, "")
      if currentHash != storedHash:
        result.add(relativeAreaPath)

  result.sort()

proc areasMissingInPlanPath(planPath: string): bool =
  ## Return true when no area markdown files exist under areas/.
  let areasPath = planPath / PlanAreasDir
  if not dirExists(areasPath):
    result = true
  else:
    var hasAreaFiles = false
    for filePath in walkDirRec(areasPath):
      if filePath.toLowerAscii().endsWith(".md"):
        hasAreaFiles = true
    result = not hasAreaFiles

proc nextTicketId(planPath: string): int =
  ## Compute the next monotonic ticket ID by scanning all ticket states.
  result = 1
  for stateDir in [PlanTicketsOpenDir, PlanTicketsInProgressDir, PlanTicketsDoneDir, PlanTicketsStuckDir]:
    for ticketPath in listMarkdownFiles(planPath / stateDir):
      let ticketName = splitFile(ticketPath).name
      let dashPos = ticketName.find('-')
      if dashPos > 0:
        let prefix = ticketName[0..<dashPos]
        if prefix.allCharsInSet(Digits):
          let parsedId = parseInt(prefix)
          if parsedId >= result:
            result = parsedId + 1

proc oldestOpenTicketInPlanPath(planPath: string): string =
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

proc worktreePathForTicket(repoPath: string, ticketRelPath: string): string =
  ## Build a deterministic absolute worktree path for a ticket.
  let ticketName = splitFile(ticketRelPath).name
  let root = managedTicketWorktreeRootPath(repoPath)
  result = absolutePath(root / ticketName)

proc listGitWorktreePaths(repoPath: string): seq[string] =
  ## Return absolute worktree paths from git worktree list.
  let allArgs = @["-C", repoPath, "worktree", "list", "--porcelain"]
  let process = startProcess("git", args = allArgs, options = {poUsePath, poStdErrToStdOut})
  let output = process.outputStream.readAll()
  let rc = process.waitForExit()
  process.close()
  if rc != 0:
    raise newException(IOError, fmt"git worktree list failed: {output.strip()}")

  for line in output.splitLines():
    if line.startsWith("worktree "):
      result.add(line["worktree ".len..^1].strip())

proc cleanupLegacyManagedTicketWorktrees(repoPath: string): seq[string] =
  ## Remove legacy repo-local managed ticket worktrees from older versions.
  let legacyRoot = normalizeAbsolutePath(repoPath / LegacyManagedWorktreeRoot)
  for path in listGitWorktreePaths(repoPath):
    let normalizedPath = normalizeAbsolutePath(path)
    if normalizedPath.startsWith(legacyRoot & "/"):
      discard gitCheck(repoPath, "worktree", "remove", "--force", path)
      if dirExists(path):
        removeDir(path)
      result.add(path)

  if dirExists(legacyRoot):
    removeDir(legacyRoot)

proc ensureWorktreeCreated(repoPath: string, ticketRelPath: string): tuple[branch: string, path: string] =
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

proc writeAreasAndCommit(planPath: string, docs: seq[AreaDocument]): bool =
  ## Write generated area files and commit only when contents changed.
  var hasChanges = false
  for doc in docs:
    let relPath = normalizeAreaPath(doc.path)
    let target = planPath / PlanAreasDir / relPath
    createDir(parentDir(target))
    if fileExists(target):
      if readFile(target) != doc.content:
        writeFile(target, doc.content)
        hasChanges = true
    else:
      writeFile(target, doc.content)
      hasChanges = true

  if hasChanges:
    gitRun(planPath, "add", PlanAreasDir)
    if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
      gitRun(planPath, "commit", "-m", AreaCommitMessage)

  result = hasChanges

proc writeTicketsForArea(
  planPath: string,
  areaRelPath: string,
  docs: seq[TicketDocument],
  nextId: var int,
): bool =
  ## Write manager-generated tickets for one area into tickets/open.
  let areaId = areaIdFromAreaPath(areaRelPath)
  var hasChanges = false

  for doc in docs:
    let slug = normalizeTicketSlug(doc.slug)
    let ticketPath = planPath / PlanTicketsOpenDir / fmt"{nextId:04d}-{slug}.md"
    let body = doc.content.strip()
    if body.len == 0:
      raise newException(ValueError, "ticket content cannot be empty")

    let existingArea = parseAreaFromTicketContent(body)
    var ticketContent = body
    if existingArea.len == 0:
      ticketContent &= "\n\n" & AreaFieldPrefix & " " & areaId & "\n"
    elif existingArea != areaId:
      raise newException(ValueError, fmt"ticket area '{existingArea}' does not match area '{areaId}'")
    else:
      ticketContent &= "\n"

    writeFile(ticketPath, ticketContent)
    hasChanges = true
    inc nextId

  result = hasChanges

proc parsePort(rawPort: string, scheme: string): int =
  ## Parse the port value from a URI, falling back to scheme defaults.
  if rawPort.len > 0:
    result = parseInt(rawPort)
  elif scheme == "https":
    result = 443
  else:
    result = 80

  if result < 1 or result > 65535:
    raise newException(ValueError, fmt"invalid endpoint port: {result}")

proc parseEndpoint*(endpointUrl: string): OrchestratorEndpoint =
  ## Parse the orchestrator HTTP endpoint from a URL.
  let clean = endpointUrl.strip()
  let resolved = if clean.len > 0: clean else: DefaultLocalEndpoint
  let parsed = parseUri(resolved)

  if parsed.scheme.len == 0:
    raise newException(ValueError, fmt"invalid endpoint URL (missing scheme): {resolved}")
  if parsed.hostname.len == 0:
    raise newException(ValueError, fmt"invalid endpoint URL (missing hostname): {resolved}")

  result = OrchestratorEndpoint(
    address: parsed.hostname,
    port: parsePort(parsed.port, parsed.scheme),
  )

proc loadOrchestratorEndpoint*(repoPath: string): OrchestratorEndpoint =
  ## Load and parse the orchestrator endpoint from repo configuration.
  let cfg = loadConfig(repoPath)
  result = parseEndpoint(cfg.endpoints.local)

proc loadSpecFromPlan*(repoPath: string): string =
  ## Load spec.md by opening the scriptorium/plan branch in a temporary worktree.
  result = withPlanWorktree(repoPath, proc(planPath: string): string =
    loadSpecFromPlanPath(planPath)
  )

proc areasMissing*(repoPath: string): bool =
  ## Return true when the plan branch has no area markdown files.
  result = withPlanWorktree(repoPath, proc(planPath: string): bool =
    areasMissingInPlanPath(planPath)
  )

proc areasNeedingTickets*(repoPath: string): seq[string] =
  ## Return area files that are eligible for manager ticket generation.
  result = withPlanWorktree(repoPath, proc(planPath: string): seq[string] =
    areasNeedingTicketsInPlanPath(planPath)
  )

proc oldestOpenTicket*(repoPath: string): string =
  ## Return the oldest open ticket path in the plan branch.
  result = withPlanWorktree(repoPath, proc(planPath: string): string =
    oldestOpenTicketInPlanPath(planPath)
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

proc hasRunnableSpec*(repoPath: string): bool =
  ## Return true when spec.md is present and contains actionable content.
  result = withPlanWorktree(repoPath, proc(planPath: string): bool =
    hasRunnableSpecInPlanPath(planPath)
  )

proc listActiveTicketWorktrees*(repoPath: string): seq[ActiveTicketWorktree] =
  ## Return active in-progress ticket worktrees from the plan branch.
  result = withPlanWorktree(repoPath, proc(planPath: string): seq[ActiveTicketWorktree] =
    listActiveTicketWorktreesInPlanPath(planPath)
  )

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

proc syncAreasFromSpec*(repoPath: string, generateAreas: ArchitectAreaGenerator): bool =
  ## Generate and persist areas when plan/areas has no markdown files.
  if generateAreas.isNil:
    raise newException(ValueError, "architect area generator is required")

  let cfg = loadConfig(repoPath)
  result = withLockedPlanWorktree(repoPath, proc(planPath: string): bool =
    let missing = areasMissingInPlanPath(planPath)
    if missing:
      let spec = loadSpecFromPlanPath(planPath)
      let docs = generateAreas(cfg.agents.architect.model, spec)
      discard writeAreasAndCommit(planPath, docs)
      writeSpecHashMarker(planPath)
      gitRun(planPath, "add", SpecHashMarkerPath)
      if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
        gitRun(planPath, "commit", "-m", SpecHashCommitMessage)
      true
    else:
      false
  )

proc architectShouldRun(planPath: string): bool =
  ## Determine whether the architect needs to run based on spec content hash.
  if areasMissingInPlanPath(planPath):
    return true  # No areas at all — first run
  let storedHash = readSpecHashMarker(planPath)
  if storedHash == "":
    return false  # Legacy: areas exist but no hash — migration writes hash, skip this tick
  let currentHash = computeContentHash(loadSpecFromPlanPath(planPath))
  return storedHash != currentHash

proc runArchitectAreas*(repoPath: string, runner: AgentRunner = runAgent): bool =
  ## Run one architect pass that writes area files directly in the plan worktree.
  if runner.isNil:
    raise newException(ValueError, "agent runner is required")

  let cfg = loadConfig(repoPath)
  result = withLockedPlanWorktree(repoPath, proc(planPath: string): bool =
    if not hasRunnableSpecInPlanPath(planPath):
      return false

    # Migration: write spec hash marker for existing areas without one
    if not areasMissingInPlanPath(planPath) and not fileExists(planPath / SpecHashMarkerPath):
      writeSpecHashMarker(planPath)
      gitRun(planPath, "add", SpecHashMarkerPath)
      if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
        gitRun(planPath, "commit", "-m", "scriptorium: initialize spec hash marker")

    if not architectShouldRun(planPath):
      return false

    let spec = loadSpecFromPlanPath(planPath)
    discard runner(AgentRunRequest(
      prompt: buildArchitectAreasPrompt(repoPath, planPath, spec),
      workingDir: planPath,
      harness: cfg.agents.architect.harness,
      model: cfg.agents.architect.model,
      reasoningEffort: cfg.agents.architect.reasoningEffort,
      ticketId: ArchitectAreasTicketId,
      attempt: DefaultAgentAttempt,
      skipGitRepoCheck: true,
      logRoot: planAgentLogRoot(ArchitectAreasLogDirName),
      maxAttempts: DefaultAgentMaxAttempts,
      onEvent: proc(event: AgentStreamEvent) =
        if event.kind == agentEventTool:
          logDebug(fmt"architect: {event.text}"),
    ))

    gitRun(planPath, "add", PlanAreasDir)
    if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
      gitRun(planPath, "commit", "-m", AreaCommitMessage)

    # Write updated spec hash marker after architect commits
    writeSpecHashMarker(planPath)
    gitRun(planPath, "add", SpecHashMarkerPath)
    if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
      gitRun(planPath, "commit", "-m", SpecHashCommitMessage)
    true
  )

proc updateSpecFromArchitect*(
  repoPath: string,
  prompt: string,
  runner: AgentRunner,
): bool =
  ## Update spec.md from one architect run and commit when content changes.
  if runner.isNil:
    raise newException(ValueError, "agent runner is required")
  if prompt.strip().len == 0:
    raise newException(ValueError, "plan prompt is required")

  let cfg = loadConfig(repoPath)
  result = withLockedPlanWorktree(repoPath, proc(planPath: string): bool =
    let existingSpec = loadSpecFromPlanPath(planPath)
    discard runPlanArchitectRequest(
      runner,
      planPath,
      cfg.agents.architect,
      buildArchitectPlanPrompt(repoPath, planPath, prompt, existingSpec),
      PlanSpecTicketId,
    )
    enforceWriteAllowlist(planPath, [PlanSpecPath], PlanWriteScopeName)

    let updatedSpec = loadSpecFromPlanPath(planPath)
    if updatedSpec == existingSpec:
      false
    else:
      gitRun(planPath, "add", PlanSpecPath)
      if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
        gitRun(planPath, "commit", "-m", PlanSpecCommitMessage)
      true
  )

proc updateSpecFromArchitect*(repoPath: string, prompt: string): bool =
  ## Update spec.md using the default architect model backend.
  result = updateSpecFromArchitect(repoPath, prompt, runAgent)

proc syncTicketsFromAreas*(repoPath: string, generateTickets: ManagerTicketGenerator): bool =
  ## Generate and persist tickets for areas without active work.
  if generateTickets.isNil:
    raise newException(ValueError, "manager ticket generator is required")

  let cfg = loadConfig(repoPath)
  result = withLockedPlanWorktree(repoPath, proc(planPath: string): bool =
    let areasToProcess = areasNeedingTicketsInPlanPath(planPath)
    if areasToProcess.len == 0:
      false
    else:
      var nextId = nextTicketId(planPath)
      var hasChanges = false
      for areaRelPath in areasToProcess:
        let areaContent = readFile(planPath / areaRelPath)
        let docs = generateTickets(cfg.agents.manager.model, areaRelPath, areaContent)
        if writeTicketsForArea(planPath, areaRelPath, docs, nextId):
          hasChanges = true

      if hasChanges:
        gitRun(planPath, "add", PlanTicketsOpenDir)
        if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
          gitRun(planPath, "commit", "-m", TicketCommitMessage)

      # Update area hashes after ticket generation
      let currentHashes = computeAllAreaHashes(planPath)
      writeAreaHashes(planPath, currentHashes)
      gitRun(planPath, "add", AreaHashesPath)
      if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
        gitRun(planPath, "commit", "-m", AreaHashesCommitMessage)

      hasChanges
  )

proc runManagerTickets*(repoPath: string, runner: AgentRunner = runAgent): bool =
  ## Run a single batched manager pass that writes ticket files for all areas.
  if runner.isNil:
    raise newException(ValueError, "agent runner is required")

  let cfg = loadConfig(repoPath)
  let repoDirtyStateBefore = snapshotDirtyStateInGitPath(repoPath)
  result = withLockedPlanWorktree(repoPath, proc(planPath: string): bool =
    if not hasRunnableSpecInPlanPath(planPath):
      false
    else:
      let areasToProcess = areasNeedingTicketsInPlanPath(planPath)
      if areasToProcess.len == 0:
        false
      else:
        var areas: seq[tuple[relPath: string, content: string]]
        for areaRelPath in areasToProcess:
          areas.add((relPath: areaRelPath, content: readFile(planPath / areaRelPath)))
        let nextId = nextTicketId(planPath)
        discard runner(AgentRunRequest(
          prompt: buildManagerTicketsBatchPrompt(repoPath, planPath, areas, nextId),
          workingDir: planPath,
          harness: cfg.agents.manager.harness,
          model: cfg.agents.manager.model,
          reasoningEffort: cfg.agents.manager.reasoningEffort,
          ticketId: ManagerTicketIdPrefix & "batch",
          attempt: DefaultAgentAttempt,
          skipGitRepoCheck: true,
          logRoot: planAgentLogRoot(ManagerLogDirName / "batch"),
          maxAttempts: DefaultAgentMaxAttempts,
          onEvent: proc(event: AgentStreamEvent) =
            if event.kind == agentEventTool:
              logDebug(fmt"manager[batch]: {event.text}"),
        ))
        enforceWritePrefixAllowlist(planPath, [PlanTicketsOpenDir, PlanTicketsDoneDir], ManagerWriteScopeName)
        enforceGitPathUnchanged(repoPath, repoDirtyStateBefore, ManagerWriteScopeName)

        gitRun(planPath, "add", PlanTicketsOpenDir)
        gitRun(planPath, "add", PlanTicketsDoneDir)
        if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
          gitRun(planPath, "commit", "-m", TicketCommitMessage)

        # Update area hashes after ticket generation
        let currentHashes = computeAllAreaHashes(planPath)
        writeAreaHashes(planPath, currentHashes)
        gitRun(planPath, "add", AreaHashesPath)
        if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
          gitRun(planPath, "commit", "-m", AreaHashesCommitMessage)

        true
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

proc dependenciesSatisfied(ticketContent: string, doneIds: HashSet[string]): bool =
  ## Check whether all declared dependencies are in the done set.
  let deps = parseDependsFromTicketContent(ticketContent)
  if deps.len == 0:
    return true
  for dep in deps:
    if dep notin doneIds:
      return false
  return true

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

proc executeAssignedTicket*(
  repoPath: string,
  assignment: TicketAssignment,
  runner: AgentRunner = runAgent,
): AgentRunResult =
  ## Run the coding agent for an assigned in-progress ticket and persist run notes.
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
  let ticketContent = withPlanWorktree(repoPath, proc(planPath: string): string =
    let ticketPath = planPath / ticketRelPath
    if not fileExists(ticketPath):
      raise newException(ValueError, fmt"ticket does not exist in plan branch: {ticketRelPath}")
    readFile(ticketPath)
  )

  logDebug(fmt"executeAssignedTicket: buildCodingAgentPrompt")
  let ticketId = ticketIdFromTicketPath(ticketRelPath)
  let initialPrompt = buildCodingAgentPrompt(repoPath, assignment.worktree, ticketRelPath, ticketContent)

  var currentPrompt = initialPrompt
  var currentAttemptBase = DefaultAgentAttempt
  var totalAttemptsUsed = 0
  var submitSummary = ""
  let model = cfg.agents.coding.model
  let maxAttempts = cfg.timeouts.codingAgentMaxAttempts

  setActiveTicketWorktree(assignment.worktree, ticketId)
  defer: clearActiveTicketWorktree(ticketId)

  while totalAttemptsUsed < maxAttempts:
    let attemptsForThisCall = maxAttempts - totalAttemptsUsed
    logInfo(fmt"ticket {ticketId}: coding agent started (model={model}, attempt {currentAttemptBase}/{maxAttempts})")
    let agentStartTime = epochTime()
    let request = AgentRunRequest(
      prompt: currentPrompt,
      workingDir: assignment.worktree,
      harness: cfg.agents.coding.harness,
      model: cfg.agents.coding.model,
      reasoningEffort: cfg.agents.coding.reasoningEffort,
      mcpEndpoint: cfg.endpoints.local,
      ticketId: ticketId,
      attempt: currentAttemptBase,
      skipGitRepoCheck: true,
      noOutputTimeoutMs: cfg.timeouts.codingAgentNoOutputTimeoutMs,
      hardTimeoutMs: cfg.timeouts.codingAgentHardTimeoutMs,
      maxAttempts: attemptsForThisCall,
      onEvent: proc(event: AgentStreamEvent) =
        if event.kind == agentEventTool:
          logDebug(fmt"coding[{ticketId}]: {event.text}")
        elif event.kind == agentEventStatus:
          logDebug(fmt"coding[{ticketId}]: status {event.text}"),
    )
    discard consumeSubmitPrSummary(ticketId)

    logDebug(fmt"executeAssignedTicket: running coding agent (attempt {currentAttemptBase}/{maxAttempts})")
    let agentResult = runner(request)
    result = agentResult
    totalAttemptsUsed += agentResult.attemptCount

    let agentWallTime = epochTime() - agentStartTime
    let agentWallDuration = formatDuration(agentWallTime)
    let isStall = agentResult.exitCode == 0 and agentResult.timeoutKind == "none"
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
    discard withLockedPlanWorktree(repoPath, proc(planPath: string): int =
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
    let dirtyCheck = runCommandCapture(assignment.worktree, "git", @["status", "--porcelain"])
    if dirtyCheck.exitCode == 0 and dirtyCheck.output.strip().len > 0:
      logInfo(fmt"executeAssignedTicket: auto-committing uncommitted changes")
      gitRun(assignment.worktree, "add", "-A")
      gitRun(assignment.worktree, "commit", "-m", "scriptorium: auto-commit agent changes")
    logDebug(fmt"executeAssignedTicket: enqueueing merge request")
    discard enqueueMergeRequest(repoPath, assignment, submitSummary)
  else:
    let attempts = ticketAttemptCounts.getOrDefault(ticketId, totalAttemptsUsed)
    let startTime = ticketStartTimes.getOrDefault(ticketId, 0.0)
    let totalWall = if startTime > 0.0: formatDuration(epochTime() - startTime) else: "unknown"
    logInfo(fmt"ticket {ticketId}: in-progress -> open (reopened, reason=no submit_pr, attempts={attempts}, total wall={totalWall})")
    sessionStats.ticketsReopened += 1
    let failureReason = case result.timeoutKind
      of "hard": "timeout_hard"
      of "no-output": "timeout_no_output"
      else: "stall"
    let metricsNote = formatMetricsNote(ticketId, "reopened", failureReason).strip()
    let stallWallSeconds = if startTime > 0.0: int(epochTime() - startTime) else: 0
    cleanupTicketTimings(ticketId)
    discard withLockedPlanWorktree(repoPath, proc(planPath: string): int =
      let ticketPath = planPath / ticketRelPath
      let openRelPath = PlanTicketsOpenDir / extractFilename(ticketRelPath)
      if fileExists(ticketPath):
        let currentContent = readFile(ticketPath)
        let contentWithMetrics = runPostAnalysis(currentContent.strip() & "\n\n" & metricsNote & "\n", ticketId, "reopened", attempts, stallWallSeconds)
        writeFile(ticketPath, contentWithMetrics)
        moveFile(ticketPath, planPath / openRelPath)
        gitRun(planPath, "add", "-A", PlanTicketsInProgressDir, PlanTicketsOpenDir)
        if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
          gitRun(planPath, "commit", "-m", TicketAgentFailReopenCommitPrefix & " " & ticketId)
      0
    )

proc runTicketPrediction*(repoPath: string, ticketRelPath: string, runner: AgentRunner = runAgent) =
  ## Run a best-effort prediction for a ticket and persist results to the plan branch.
  let ticketId = ticketIdFromTicketPath(ticketRelPath)
  let ticketContent = withPlanWorktree(repoPath, proc(planPath: string): string =
    readFile(planPath / ticketRelPath)
  )
  try:
    let prediction = predictTicketDifficulty(repoPath, ticketRelPath, ticketContent, runner)
    discard withLockedPlanWorktree(repoPath, proc(planPath: string): int =
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

proc executeOldestOpenTicket*(repoPath: string, runner: AgentRunner = runAgent): AgentRunResult =
  ## Assign the oldest open ticket and execute it with the coding agent.
  let assignment = assignOldestOpenTicket(repoPath)
  if assignment.inProgressTicket.len == 0:
    logDebug("no open tickets to execute")
    result = AgentRunResult()
  else:
    let ticketId = ticketIdFromTicketPath(assignment.inProgressTicket)
    runTicketPrediction(repoPath, assignment.inProgressTicket, runner)
    result = executeAssignedTicket(repoPath, assignment, runner)
    result.ticketId = ticketId

proc agentWorkerThread(args: AgentThreadArgs) {.thread.} =
  ## Run executeAssignedTicket in a background thread and send the result to the channel.
  {.cast(gcsafe).}:
    let runner: AgentRunner = if not agentRunnerOverride.isNil: agentRunnerOverride else: runAgent
    let agentResult = executeAssignedTicket(args.repoPath, args.assignment, runner)
    agentResultChan.send((ticketId: args.ticketId, result: agentResult))

proc runningAgentCount*(): int =
  ## Return the number of currently running agent slots.
  result = runningAgentSlots.len

proc emptySlotCount*(maxAgents: int): int =
  ## Return the number of available agent slots.
  result = maxAgents - runningAgentSlots.len

proc startAgentAsync*(repoPath: string, assignment: TicketAssignment, maxAgents: int) =
  ## Start a coding agent in a background thread for the given assignment.
  ensureAgentResultChanOpen()
  let ticketId = ticketIdFromTicketPath(assignment.inProgressTicket)
  let slot = AgentSlot(
    ticketId: ticketId,
    branch: assignment.branch,
    worktree: assignment.worktree,
    startTime: epochTime(),
  )
  runningAgentSlots.add(slot)
  let threadPtr = create(Thread[AgentThreadArgs])
  let args: AgentThreadArgs = (
    repoPath: repoPath,
    assignment: assignment,
    ticketId: ticketId,
  )
  createThread(threadPtr[], agentWorkerThread, args)
  runningAgentThreadPtrs.add(threadPtr)
  let running = runningAgentSlots.len
  logInfo(&"agent slots: {running}/{maxAgents} (ticket {ticketId} started)")

proc checkCompletedAgents*(): seq[AgentCompletionResult] =
  ## Poll the result channel for completed agents and clean up their slots and threads.
  ensureAgentResultChanOpen()
  while true:
    let (hasData, completion) = agentResultChan.tryRecv()
    if not hasData:
      break
    result.add(completion)
    var slotIdx = -1
    for i, slot in runningAgentSlots:
      if slot.ticketId == completion.ticketId:
        slotIdx = i
        break
    if slotIdx >= 0:
      runningAgentSlots.delete(slotIdx)
      joinThread(runningAgentThreadPtrs[slotIdx][])
      dealloc(runningAgentThreadPtrs[slotIdx])
      runningAgentThreadPtrs.delete(slotIdx)

proc joinAllAgentThreads*() =
  ## Block until all running agent threads complete and clean up.
  for i in 0..<runningAgentThreadPtrs.len:
    joinThread(runningAgentThreadPtrs[i][])
    dealloc(runningAgentThreadPtrs[i])
  runningAgentSlots.setLen(0)
  runningAgentThreadPtrs.setLen(0)

proc createOrchestratorServer*(): HttpMcpServer =
  ## Create the orchestrator MCP HTTP server.
  ensureSubmitPrLockInitialized()
  let server = newMcpServer(OrchestratorServerName, OrchestratorServerVersion)
  let submitPrTool = McpTool(
    name: "submit_pr",
    description: "Signal that ticket work is complete and ready for merge queue",
    inputSchema: %*{
      "type": "object",
      "properties": {
        "summary": {
          "type": "string",
          "description": "Short summary of changes"
        },
        "ticket_id": {
          "type": "string",
          "description": "Ticket ID for this submission (optional, used in parallel mode)"
        }
      },
      "required": ["summary"]
    },
  )
  let submitPrHandler: ToolHandler = proc(arguments: JsonNode): JsonNode {.gcsafe.} =
    let summary = arguments["summary"].getStr()
    let reqTicketId = if arguments.hasKey("ticket_id"): arguments["ticket_id"].getStr() else: ""
    let active = getActiveTicketWorktree(reqTicketId)
    let ticketLabel = if active.ticketId.len > 0: active.ticketId else: "unknown"

    if active.worktreePath.len == 0:
      {.cast(gcsafe).}:
        logInfo(&"ticket {ticketLabel}: submit_pr pre-check: SKIP (no active worktree)")
      recordSubmitPrSummary(summary, active.ticketId)
      return %*"Merge request enqueued."

    let testStartTime = epochTime()
    let testResult = runWorktreeMakeTest(active.worktreePath)
    let testWallTime = epochTime() - testStartTime
    let testExitCode = testResult.exitCode
    {.cast(gcsafe).}:
      let testWallDuration = formatDuration(testWallTime)
      let testStatus = if testExitCode == 0: "PASS" else: "FAIL"
      logInfo(&"ticket {ticketLabel}: submit_pr pre-check: {testStatus} (exit={testExitCode}, wall={testWallDuration})")

    if testExitCode != 0:
      let outputTail = truncateTail(testResult.output.strip(), SubmitPrTestOutputMaxChars)
      return %*(&"Pre-submit test gate failed (exit={testExitCode}). Fix the failing tests and call submit_pr again.\n\n{outputTail}")

    recordSubmitPrSummary(summary, active.ticketId)
    %*"Merge request enqueued."
  server.registerTool(submitPrTool, submitPrHandler)
  let submitReviewTool = McpTool(
    name: "submit_review",
    description: "Submit a review decision for the current ticket",
    inputSchema: %*{
      "type": "object",
      "properties": {
        "action": {
          "type": "string",
          "enum": ["approve", "request_changes"],
          "description": "Review action to take"
        },
        "feedback": {
          "type": "string",
          "description": "Feedback for the review (required when action is request_changes)"
        }
      },
      "required": ["action"]
    },
  )
  let submitReviewHandler: ToolHandler = proc(arguments: JsonNode): JsonNode {.gcsafe.} =
    let action = arguments["action"].getStr()
    if action != "approve" and action != "request_changes":
      return %*"Invalid action. Must be \"approve\" or \"request_changes\"."
    let feedback = if arguments.hasKey("feedback"): arguments["feedback"].getStr() else: ""
    if action == "request_changes" and feedback.len == 0:
      return %*"Feedback is required when action is \"request_changes\"."
    recordReviewDecision(action, feedback)
    %*"Review decision recorded."
  server.registerTool(submitReviewTool, submitReviewHandler)
  result = newHttpMcpServer(server, logEnabled = false)

proc handlePosixSignal(signalNumber: cint) {.noconv.} =
  ## Stop the orchestrator loop on SIGINT/SIGTERM.
  logInfo(fmt"shutdown: signal {signalNumber} received")
  shouldRun = false

proc handleInteractivePlanCtrlC() {.noconv.} =
  ## Request shutdown of one interactive planning session on Ctrl+C.
  interactivePlanInterrupted = true

proc inputErrorIndicatesInterrupt(message: string): bool =
  ## Return true when one input error string indicates interrupted input.
  let lower = message.toLowerAscii()
  result = lower.contains("interrupted") or lower.contains("eintr")

proc installSignalHandlers() =
  ## Install signal handlers used by the orchestrator run loop.
  posix.signal(SIGINT, handlePosixSignal)
  posix.signal(SIGTERM, handlePosixSignal)

proc runHttpServer(args: ServerThreadArgs) {.thread.} =
  ## Run the MCP HTTP server in a background thread.
  args.httpServer.serve(args.port, args.address)

proc hasPlanBranch(repoPath: string): bool =
  ## Return true when the repository has the scriptorium plan branch.
  result = gitCheck(repoPath, "rev-parse", "--verify", PlanBranch) == 0

proc masterHeadCommit(repoPath: string): string =
  ## Return the current master branch commit SHA.
  let process = startProcess(
    "git",
    args = @["-C", repoPath, "rev-parse", "master"],
    options = {poUsePath, poStdErrToStdOut},
  )
  let output = process.outputStream.readAll()
  let rc = process.waitForExit()
  process.close()
  if rc != 0:
    raise newException(IOError, fmt"git rev-parse master failed: {output.strip()}")
  result = output.strip()

proc readHealthCache*(planPath: string): Table[string, HealthCacheEntry] =
  ## Read health/cache.json from a plan worktree path and return the cache table.
  let cachePath = planPath / HealthCacheRelPath
  if not fileExists(cachePath):
    return initTable[string, HealthCacheEntry]()
  let raw = readFile(cachePath)
  let rootNode = parseJson(raw)
  for commitHash, entryNode in rootNode.pairs:
    var entry = HealthCacheEntry(
      healthy: entryNode["healthy"].getBool(),
      timestamp: entryNode["timestamp"].getStr(),
      test_exit_code: entryNode["test_exit_code"].getInt(),
      integration_test_exit_code: entryNode["integration_test_exit_code"].getInt(),
      test_wall_seconds: entryNode["test_wall_seconds"].getInt(),
      integration_test_wall_seconds: entryNode["integration_test_wall_seconds"].getInt(),
    )
    result[commitHash] = entry

proc writeHealthCache*(planPath: string, cache: Table[string, HealthCacheEntry]) =
  ## Write the health cache table to health/cache.json in a plan worktree path.
  let cacheDir = planPath / HealthCacheDir
  if not dirExists(cacheDir):
    createDir(cacheDir)
  var rootNode = newJObject()
  for commitHash, entry in cache.pairs:
    var entryNode = newJObject()
    entryNode["healthy"] = newJBool(entry.healthy)
    entryNode["timestamp"] = newJString(entry.timestamp)
    entryNode["test_exit_code"] = newJInt(entry.test_exit_code)
    entryNode["integration_test_exit_code"] = newJInt(entry.integration_test_exit_code)
    entryNode["test_wall_seconds"] = newJInt(entry.test_wall_seconds)
    entryNode["integration_test_wall_seconds"] = newJInt(entry.integration_test_wall_seconds)
    rootNode[commitHash] = entryNode
  writeFile(planPath / HealthCacheRelPath, $rootNode)

proc commitHealthCache(planPath: string) =
  ## Stage and commit health/cache.json on the plan branch.
  gitRun(planPath, "add", HealthCacheRelPath)
  gitRun(planPath, "commit", "-m", HealthCacheCommitMessage)

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

proc resetSessionStats*() =
  ## Reset session statistics to default values.
  sessionStats = SessionStats(startTime: epochTime())

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

proc waitForServerReady(address: string, port: int, timeoutMs: int = ServerReadyTimeoutMs) =
  ## Poll the MCP endpoint until it responds or timeout is reached.
  let url = fmt"http://{address}:{port}/mcp"
  let deadline = epochTime() + float(timeoutMs) / 1000.0
  while epochTime() < deadline:
    try:
      let client = newHttpClient(timeout = 500)
      defer: client.close()
      discard client.request(url, httpMethod = HttpGet)
      logInfo(fmt"MCP server ready on {address}:{port}")
      return
    except:
      sleep(ServerReadyPollIntervalMs)
  logWarn(fmt"MCP server not ready after {timeoutMs}ms, proceeding anyway")

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
  httpServer.close()
  logDebug("waiting for HTTP server thread to exit")
  joinThread(serverThread)
  logDebug("HTTP server thread exited")

proc runOrchestratorForTicks*(repoPath: string, maxTicks: int, runner: AgentRunner = runAgent) =
  ## Run a bounded orchestrator loop without starting the MCP HTTP server.
  shouldRun = true
  runOrchestratorMainLoop(repoPath, maxTicks, runner)
  shouldRun = false

proc buildInteractivePlanPrompt*(repoPath: string, planPath: string, spec: string, history: seq[PlanTurn], userMsg: string): string =
  ## Assemble the multi-turn architect prompt with spec, history, and current message.
  var conversationHistory = ""
  if history.len > 0:
    conversationHistory = "\nConversation history:\n"
    for turn in history:
      conversationHistory &= fmt"\n[{turn.role}]: {turn.text.strip()}\n"

  result = renderPromptTemplate(
    ArchitectPlanInteractiveTemplate,
    [
      (name: "PLAN_SCOPE", value: buildPlanScopePrompt(repoPath, planPath).strip()),
      (name: "CURRENT_SPEC", value: spec.strip()),
      (name: "CONVERSATION_HISTORY", value: conversationHistory),
      (name: "USER_MESSAGE", value: userMsg.strip()),
    ],
  )

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
        planPath,
        cfg.agents.architect,
        prompt,
        PlanSessionTicketId,
        streamEventHandler,
        PlanHeartbeatIntervalMs,
      )
      enforceWriteAllowlist(planPath, [PlanSpecPath], PlanWriteScopeName)

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

proc buildInteractiveAskPrompt*(repoPath: string, planPath: string, spec: string, history: seq[PlanTurn], userMsg: string): string =
  ## Assemble the multi-turn read-only architect prompt with spec, history, and current message.
  var conversationHistory = ""
  if history.len > 0:
    conversationHistory = "\nConversation history:\n"
    for turn in history:
      conversationHistory &= fmt"\n[{turn.role}]: {turn.text.strip()}\n"

  result = renderPromptTemplate(
    ArchitectAskInteractiveTemplate,
    [
      (name: "PLAN_SCOPE", value: buildPlanScopePrompt(repoPath, planPath).strip()),
      (name: "CURRENT_SPEC", value: spec.strip()),
      (name: "CONVERSATION_HISTORY", value: conversationHistory),
      (name: "USER_MESSAGE", value: userMsg.strip()),
    ],
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
