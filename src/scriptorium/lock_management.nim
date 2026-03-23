import
  std/[locks, os, posix, strformat, strutils, times],
  jsony,
  ./git_ops

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

proc withPlanWorktreeImpl*[T](repoPath: string, operation: proc(planPath: string): T): T =
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

proc withPlanWorktree*[T](repoPath: string, operation: proc(planPath: string): T): T =
  ## Thread-safe plan worktree access for read-only operations.
  ensurePlanWorktreeLockInitialized()
  {.cast(gcsafe).}:
    acquire(planWorktreeLock)
    defer: release(planWorktreeLock)
    result = withPlanWorktreeImpl(repoPath, operation)

proc withLockedPlanWorktree*[T](repoPath: string, operation: proc(planPath: string): T): T =
  ## Thread-safe plan worktree access with file-based repo lock for write operations.
  ensurePlanWorktreeLockInitialized()
  {.cast(gcsafe).}:
    acquire(planWorktreeLock)
    defer: release(planWorktreeLock)
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

proc releaseOrchestratorPidGuard*(repoPath: string) =
  ## Delete the orchestrator PID file on clean shutdown.
  let pidPath = orchestratorPidPath(repoPath)
  if fileExists(pidPath):
    removeFile(pidPath)
