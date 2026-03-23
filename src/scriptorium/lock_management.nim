import
  std/[locks, os, posix, strformat, strutils, times],
  jsony,
  ./[git_ops, logging]

var
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
    let normalizedRepoPath = normalizeAbsolutePath(repoPath)
    raise newException(IOError, &"another planner/manager is active for {normalizedRepoPath}")

  let pidPath = lockPath / ManagedRepoLockPidFileName
  let currentPid = getCurrentProcessId()
  writeFile(pidPath, &"{currentPid}\n")
  logDebug(&"repo lock acquired: {lockPath}")
  defer:
    if fileExists(pidPath):
      removeFile(pidPath)
    if dirExists(lockPath):
      removeDir(lockPath)
    logDebug(&"repo lock released: {lockPath}")

  result = operation()

proc ensurePlanWorktreeReady*(repoPath: string): string =
  ## Ensure the persistent plan worktree exists and is on the latest plan branch state.
  ## Internal: callers must hold planWorktreeLock.
  if gitCheck(repoPath, "rev-parse", "--verify", PlanBranch) != 0:
    raise newException(ValueError, "scriptorium/plan branch does not exist")

  let planWorktree = managedPlanWorktreePath(repoPath)
  let gitFile = planWorktree / ".git"

  if dirExists(planWorktree) and fileExists(gitFile):
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

proc teardownPlanWorktree*(repoPath: string) =
  ## Remove the persistent plan worktree on clean shutdown.
  let planWorktree = managedPlanWorktreePath(repoPath)
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

proc withPlanWorktreeImpl*[T](repoPath: string, operation: proc(planPath: string): T): T =
  ## Provide the persistent plan worktree to the operation.
  ## Internal: callers must hold planWorktreeLock.
  let planWorktree = ensurePlanWorktreeReady(repoPath)
  result = operation(planWorktree)

proc withPlanWorktree*[T](repoPath: string, operation: proc(planPath: string): T): T =
  ## Thread-safe plan worktree access for read-only operations.
  ensurePlanWorktreeLockInitialized()
  {.cast(gcsafe).}:
    logDebug("plan worktree lock acquiring (read-only)")
    acquire(planWorktreeLock)
    logDebug("plan worktree lock acquired (read-only)")
    defer:
      release(planWorktreeLock)
      logDebug("plan worktree lock released (read-only)")
    result = withPlanWorktreeImpl(repoPath, operation)

proc withLockedPlanWorktree*[T](repoPath: string, operation: proc(planPath: string): T): T =
  ## Thread-safe plan worktree access with file-based repo lock for write operations.
  ensurePlanWorktreeLockInitialized()
  {.cast(gcsafe).}:
    logDebug("plan worktree lock acquiring (write)")
    acquire(planWorktreeLock)
    logDebug("plan worktree lock acquired (write)")
    defer:
      release(planWorktreeLock)
      logDebug("plan worktree lock released (write)")
    result = withRepoLock(repoPath, proc(): T =
      withPlanWorktreeImpl(repoPath, operation)
    )

type
  OrchestratorPidFile* = object
    pid*: int
    timestamp*: float

proc acquireOrchestratorPidGuard*(repoPath: string) =
  ## Write the orchestrator PID file, aborting if another instance is alive.
  let pidPath = orchestratorPidPath(repoPath)
  createDir(parentDir(pidPath))

  if fileExists(pidPath):
    let raw = readFile(pidPath)
    let existing = fromJson(raw, OrchestratorPidFile)
    let killRc = posix.kill(Pid(existing.pid), 0)
    if killRc == 0:
      let startedAt = fromUnix(int64(existing.timestamp))
      let startedStr = startedAt.utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
      raise newException(IOError,
        &"Another orchestrator is already running (PID {existing.pid}, started {startedStr})")
    else:
      let errCode = int(osLastError())
      if errCode != ESRCH:
        let startedAt = fromUnix(int64(existing.timestamp))
        let startedStr = startedAt.utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
        raise newException(IOError,
          &"Another orchestrator is already running (PID {existing.pid}, started {startedStr})")
      # PID is dead — overwrite.
      stderr.writeLine(&"WARNING: Stale orchestrator PID file found for dead PID {existing.pid}, overwriting")

  let currentPid = getCurrentProcessId()
  let now = epochTime()
  let pidFile = OrchestratorPidFile(pid: currentPid, timestamp: now)
  writeFile(pidPath, pidFile.toJson())
  logInfo(&"orchestrator PID guard acquired (PID {currentPid})")

proc releaseOrchestratorPidGuard*(repoPath: string) =
  ## Delete the orchestrator PID file on clean shutdown.
  let pidPath = orchestratorPidPath(repoPath)
  if fileExists(pidPath):
    removeFile(pidPath)
    logDebug("orchestrator PID guard released")
