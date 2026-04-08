import
  std/[locks, os, posix, strformat, strutils, times],
  jsony,
  ./[git_ops, logging]

const
  RepoLockPollIntervalMs* = 1000
  RepoLockTimeoutSeconds* = 300
  AdminLockPollIntervalMs* = 1000
  WorktreeIndexLockPollMs* = 200
  WorktreeIndexLockMaxRetries* = 25

var
  # Single in-process mutex protecting the plan worktree. Each process uses
  # only one caller role, so a single lock is correct even with per-caller
  # worktree paths. Cross-process isolation is provided by the distinct
  # worktree directories.
  planWorktreeLock*: Lock
  planWorktreeLockInitialized* = false

proc ensurePlanWorktreeLockInitialized*() {.gcsafe.} =
  ## Initialize the in-process plan worktree lock once.
  if not planWorktreeLockInitialized:
    initLock(planWorktreeLock)
    planWorktreeLockInitialized = true

proc lockHolderPid*(lockPath: string): int =
  ## Return lock holder PID from pid file when present and valid.
  let pidPath = lockPath / ManagedRepoLockPidFileName
  if fileExists(pidPath):
    let pidText = readFile(pidPath).strip()
    if pidText.len > 0 and pidText.allCharsInSet(Digits):
      result = parseInt(pidText)

proc lockPathIsStale*(lockPath: string): bool =
  ## Return true when lock path exists but holder PID is no longer alive.
  ## Also detects cross-container staleness: if the lock holder PID equals
  ## our own PID, the lock is from a previous container that reused the same
  ## PID namespace slot.
  let holderPid = lockHolderPid(lockPath)
  if holderPid <= 0:
    result = false
  elif holderPid == getCurrentProcessId():
    # Same PID as us — this lock is from a previous process (e.g. previous
    # container) that happened to get the same PID. We cannot be holding a
    # lock we haven't acquired yet.
    result = true
  else:
    let killRc = posix.kill(Pid(holderPid), 0)
    if killRc == 0:
      result = false
    else:
      let errCode = int(osLastError())
      result = errCode == ESRCH

proc tryAcquireRepoLock*(lockPath: string): bool =
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

proc withRepoLock*[T](repoPath: string, operation: proc(): T): T =
  ## Acquire a per-repository lock for planner and manager writes.
  ## Waits with polling if another process holds the lock.
  let lockPath = managedRepoLockPath(repoPath)
  createDir(parentDir(lockPath))

  var acquired = tryAcquireRepoLock(lockPath)
  if not acquired and lockPathIsStale(lockPath):
    let stalePid = lockHolderPid(lockPath)
    logWarn(&"stealing stale repo lock at {lockPath} from dead PID {stalePid}")
    if dirExists(lockPath):
      removeDir(lockPath)
    acquired = tryAcquireRepoLock(lockPath)

  if not acquired:
    let holderPid = lockHolderPid(lockPath)
    let normalizedRepoPath = normalizeAbsolutePath(repoPath)
    logInfo(&"waiting for repo lock held by PID {holderPid} on {normalizedRepoPath}...")
    let deadline = epochTime() + float(RepoLockTimeoutSeconds)
    while not acquired and epochTime() < deadline:
      sleep(RepoLockPollIntervalMs)
      if lockPathIsStale(lockPath):
        let stalePid = lockHolderPid(lockPath)
        logWarn(&"stealing stale repo lock at {lockPath} from dead PID {stalePid}")
        if dirExists(lockPath):
          removeDir(lockPath)
      acquired = tryAcquireRepoLock(lockPath)

  if not acquired:
    let normalizedRepoPath = normalizeAbsolutePath(repoPath)
    raise newException(IOError,
      &"timed out after {RepoLockTimeoutSeconds}s waiting for repo lock on {normalizedRepoPath}")

  let pidPath = lockPath / ManagedRepoLockPidFileName
  let currentPid = getCurrentProcessId()
  atomicWriteFile(pidPath, &"{currentPid}\n")
  logDebug(&"repo lock acquired: {lockPath}")
  defer:
    if fileExists(pidPath):
      removeFile(pidPath)
    if dirExists(lockPath):
      removeDir(lockPath)
    logDebug(&"repo lock released: {lockPath}")

  result = operation()

type
  CommitLockFile* = object
    pid*: int
    timestamp*: float

proc withCommitLock*[T](repoPath: string, operation: proc(): T): T =
  ## Acquire a file-based transactional commit lock with retry and staleness detection.
  ## Writes a JSON payload with PID and timestamp. Stale locks (>= 30s) are stolen.
  ## Fresh locks cause polling retries up to CommitLockMaxRetries times.
  let lockPath = commitLockPath(repoPath)
  createDir(parentDir(lockPath))

  for attempt in 0 ..< CommitLockMaxRetries:
    if not fileExists(lockPath):
      # Lock file absent — acquire it.
      let currentPid = getCurrentProcessId()
      let now = epochTime()
      let payload = CommitLockFile(pid: currentPid, timestamp: now)
      atomicWriteFile(lockPath, payload.toJson())
      logDebug(&"commit lock acquired: {lockPath}")
      defer:
        if fileExists(lockPath):
          removeFile(lockPath)
        logDebug(&"commit lock released: {lockPath}")
      result = operation()
      return

    # Lock file exists — check staleness.
    var existing: CommitLockFile
    try:
      let raw = readFile(lockPath)
      existing = fromJson(raw, CommitLockFile)
    except CatchableError:
      # Corrupted lock file from a crashed process — treat as stale.
      logWarn(&"corrupted commit lock file at {lockPath}, removing as stale")
      removeFile(lockPath)
      continue
    let age = epochTime() - existing.timestamp
    if age >= float(CommitLockStalenessSeconds):
      let holderPid = existing.pid
      let durationStr = &"{age:.1f}s"
      logWarn(&"stealing stale commit lock from PID {holderPid}, held for {durationStr}")
      removeFile(lockPath)
      continue

    # Fresh lock — wait and retry.
    sleep(CommitLockPollMs)

  let maxWait = CommitLockMaxRetries * CommitLockPollMs
  let maxWaitSeconds = maxWait div 1000
  raise newException(IOError,
    &"timed out after {maxWaitSeconds}s waiting for commit lock on {lockPath}")

proc waitForWorktreeIndexLock*(lockPath: string) =
  ## Wait for a worktree index lock file to be released.
  ## Polls every WorktreeIndexLockPollMs up to WorktreeIndexLockMaxRetries times.
  if not fileExists(lockPath):
    return
  logInfo(&"waiting for worktree index lock: {lockPath}")
  for i in 1 .. WorktreeIndexLockMaxRetries:
    sleep(WorktreeIndexLockPollMs)
    if not fileExists(lockPath):
      logDebug(&"worktree index lock released after {i} retries: {lockPath}")
      return
  raise newException(IOError,
    &"timed out waiting for worktree index lock: {lockPath}")

proc ensurePlanWorktreeReady*(repoPath: string, caller: string): string =
  ## Ensure the persistent plan worktree exists and is on the latest plan branch state.
  ## Internal: callers must hold planWorktreeLock.
  if gitCheck(repoPath, "rev-parse", "--verify", PlanBranch) != 0:
    raise newException(ValueError, "scriptorium/plan branch does not exist")

  let planWorktree = managedPlanWorktreePath(repoPath, caller)
  let gitFile = planWorktree / ".git"

  if dirExists(planWorktree) and fileExists(gitFile):
    # Wait for any in-progress git operations on this worktree.
    let wtIndexLock = repoPath / ".git" / "worktrees" / caller / "index.lock"
    waitForWorktreeIndexLock(wtIndexLock)

    # Existing worktree — reset to latest plan branch tip.
    let checkRc = gitCheck(planWorktree, "rev-parse", "--git-dir")
    if checkRc != 0:
      # Worktree exists but git metadata is corrupt — recreate.
      logWarn(&"plan worktree corrupt, recreating: {planWorktree}")
      if dirExists(planWorktree):
        removeDir(planWorktree)
      discard gitCheck(repoPath, "worktree", "prune")
      addWorktreeWithRecovery(repoPath, planWorktree, PlanBranch)
      logDebug(&"plan worktree recreated: {planWorktree}")
    else:
      gitRun(planWorktree, "checkout", PlanBranch)
      gitRun(planWorktree, "reset", "--hard", PlanBranch)
      gitRun(planWorktree, "clean", "-fd")
      logDebug(&"plan worktree refreshed: {planWorktree}")
  else:
    # First time or missing — create fresh.
    logDebug(&"plan worktree creating: {planWorktree}")
    if dirExists(planWorktree):
      removeDir(planWorktree)
    discard gitCheck(repoPath, "worktree", "prune")
    try:
      addWorktreeWithRecovery(repoPath, planWorktree, PlanBranch)
    except:
      # Clean up partial state on failure.
      if dirExists(planWorktree):
        removeDir(planWorktree)
      discard gitCheck(repoPath, "worktree", "prune")
      raise
    logDebug(&"plan worktree created: {planWorktree}")

  result = planWorktree

proc teardownPlanWorktree*(repoPath: string, caller: string) =
  ## Remove the persistent plan worktree on clean shutdown.
  let planWorktree = managedPlanWorktreePath(repoPath, caller)
  if dirExists(planWorktree):
    let removeRc = gitCheck(repoPath, "worktree", "remove", "--force", planWorktree)
    if removeRc != 0:
      logWarn(&"plan worktree teardown remove failed (rc={removeRc}): {planWorktree}")
      if dirExists(planWorktree):
        removeDir(planWorktree)
    let pruneRc = gitCheck(repoPath, "worktree", "prune")
    if pruneRc != 0:
      logWarn(&"plan worktree teardown prune failed (rc={pruneRc})")
    logDebug(&"plan worktree torn down: {planWorktree}")

proc acquireAdminLock*(repoPath: string) =
  ## Acquire the admin lock, signaling that an engineer is active.
  ## Waits if another interactive session already holds it.
  let lockPath = managedAdminLockPath(repoPath)
  createDir(parentDir(lockPath))
  var logged = false
  while true:
    let acquired = tryAcquireRepoLock(lockPath)
    if acquired:
      let pidPath = lockPath / ManagedRepoLockPidFileName
      let currentPid = getCurrentProcessId()
      atomicWriteFile(pidPath, &"{currentPid}\n")
      logInfo("admin lock acquired")
      return
    if lockPathIsStale(lockPath):
      let stalePid = lockHolderPid(lockPath)
      logWarn(&"stealing stale admin lock from dead PID {stalePid}")
      if dirExists(lockPath):
        removeDir(lockPath)
      continue
    if not logged:
      let holderPid = lockHolderPid(lockPath)
      logInfo(&"waiting for admin lock held by PID {holderPid}...")
      logged = true
    sleep(AdminLockPollIntervalMs)

proc releaseAdminLock*(repoPath: string) =
  ## Release the admin lock.
  let lockPath = managedAdminLockPath(repoPath)
  let pidPath = lockPath / ManagedRepoLockPidFileName
  if fileExists(pidPath):
    removeFile(pidPath)
  if dirExists(lockPath):
    removeDir(lockPath)
  logInfo("admin lock released")

proc waitForAdminLock*(repoPath: string) =
  ## Wait until the admin lock is free or held by this process.
  let lockPath = managedAdminLockPath(repoPath)
  var logged = false
  while dirExists(lockPath):
    if lockPathIsStale(lockPath):
      return
    let holderPid = lockHolderPid(lockPath)
    if holderPid == getCurrentProcessId():
      return
    if not logged:
      logInfo(&"waiting for admin lock held by PID {holderPid}...")
      logged = true
    sleep(AdminLockPollIntervalMs)

proc withPlanWorktreeImpl*[T](repoPath: string, caller: string, operation: proc(planPath: string): T): T =
  ## Provide the persistent plan worktree to the operation.
  ## Internal: callers must hold planWorktreeLock.
  waitForAdminLock(repoPath)
  let planWorktree = ensurePlanWorktreeReady(repoPath, caller)
  result = operation(planWorktree)

proc withPlanWorktree*[T](repoPath: string, caller: string, operation: proc(planPath: string): T): T =
  ## Thread-safe plan worktree access for read-only operations.
  ensurePlanWorktreeLockInitialized()
  {.cast(gcsafe).}:
    logDebug("plan worktree lock acquiring (read-only)")
    acquire(planWorktreeLock)
    logDebug("plan worktree lock acquired (read-only)")
    defer:
      release(planWorktreeLock)
      logDebug("plan worktree lock released (read-only)")
    result = withPlanWorktreeImpl(repoPath, caller, operation)

proc withLockedPlanWorktree*[T](repoPath: string, caller: string, operation: proc(planPath: string): T): T =
  ## Thread-safe plan worktree access with file-based commit lock for write operations.
  ensurePlanWorktreeLockInitialized()
  {.cast(gcsafe).}:
    logDebug("plan worktree lock acquiring (write)")
    acquire(planWorktreeLock)
    logDebug("plan worktree lock acquired (write)")
    defer:
      release(planWorktreeLock)
      logDebug("plan worktree lock released (write)")
    result = withCommitLock(repoPath, proc(): T =
      withPlanWorktreeImpl(repoPath, caller, operation)
    )

type
  OrchestratorPidFile* = object
    pid*: int
    timestamp*: float

proc isScriptoriumProcess(pid: int): bool =
  ## Return true when the given PID corresponds to a scriptorium process.
  let cmdlinePath = "/proc/" & $pid & "/cmdline"
  if not fileExists(cmdlinePath):
    return false
  let cmdline = readFile(cmdlinePath)
  result = "scriptorium" in cmdline

proc acquireOrchestratorPidGuard*(repoPath: string) =
  ## Write the orchestrator PID file, aborting if another instance is alive.
  let pidPath = orchestratorPidPath(repoPath)
  createDir(parentDir(pidPath))

  if fileExists(pidPath):
    var existing: OrchestratorPidFile
    var parsed = false
    try:
      let raw = readFile(pidPath)
      existing = fromJson(raw, OrchestratorPidFile)
      parsed = true
    except CatchableError:
      # Corrupted PID file from a crashed process — overwrite it.
      logWarn(&"corrupted orchestrator PID file at {pidPath}, overwriting")
    if parsed:
      # Same PID as us means the file is from a previous container that reused
      # our PID namespace slot — we cannot be holding a guard we haven't acquired.
      if existing.pid == getCurrentProcessId():
        stderr.writeLine(&"WARNING: Stale orchestrator PID file found (same PID as us: {existing.pid}), overwriting")
      else:
        let killRc = posix.kill(Pid(existing.pid), 0)
        if killRc == 0 or (killRc != 0 and int(osLastError()) != ESRCH):
          # PID is alive (or we lack permission to signal it). Check if it is
          # actually a scriptorium process — in containers, low PIDs from a
          # previous run may collide with unrelated processes.
          if not isScriptoriumProcess(existing.pid):
            stderr.writeLine(&"WARNING: Stale orchestrator PID file found (PID {existing.pid} is not scriptorium), overwriting")
          else:
            let startedAt = fromUnix(int64(existing.timestamp))
            let startedStr = startedAt.utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
            raise newException(IOError,
              &"Another orchestrator is already running (PID {existing.pid}, started {startedStr})")
        else:
          # PID is dead (ESRCH) — overwrite.
          stderr.writeLine(&"WARNING: Stale orchestrator PID file found for dead PID {existing.pid}, overwriting")

  let currentPid = getCurrentProcessId()
  let now = epochTime()
  let pidFile = OrchestratorPidFile(pid: currentPid, timestamp: now)
  atomicWriteFile(pidPath, pidFile.toJson())
  logInfo(&"orchestrator PID guard acquired (PID {currentPid})")

proc releaseOrchestratorPidGuard*(repoPath: string) =
  ## Delete the orchestrator PID file on clean shutdown.
  let pidPath = orchestratorPidPath(repoPath)
  if fileExists(pidPath):
    removeFile(pidPath)
    logDebug("orchestrator PID guard released")
