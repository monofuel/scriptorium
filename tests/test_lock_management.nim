## Tests for lock management: PID guard, stale git lock cleanup, and commit lock.

import
  std/[os, posix, strformat, strutils, tempfiles, times, unittest],
  jsony,
  scriptorium/[git_ops, lock_management]

suite "orchestrator PID guard":
  test "acquireOrchestratorPidGuard writes PID file with correct content":
    let tmp = createTempDir("pid_guard_write_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    acquireOrchestratorPidGuard(tmp)
    defer: releaseOrchestratorPidGuard(tmp)

    let pidPath = orchestratorPidPath(tmp)
    check fileExists(pidPath)
    let raw = readFile(pidPath)
    let parsed = fromJson(raw, OrchestratorPidFile)
    check parsed.pid == getCurrentProcessId()
    check parsed.timestamp > 0.0

  test "releaseOrchestratorPidGuard deletes PID file":
    let tmp = createTempDir("pid_guard_release_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    acquireOrchestratorPidGuard(tmp)
    let pidPath = orchestratorPidPath(tmp)
    check fileExists(pidPath)

    releaseOrchestratorPidGuard(tmp)
    check not fileExists(pidPath)

  test "stale PID file from dead process is overwritten":
    let tmp = createTempDir("pid_guard_stale_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    # Write a PID file with a PID that is very unlikely to be alive.
    let stalePid = 2_000_000_000
    let stalePidFile = OrchestratorPidFile(pid: stalePid, timestamp: 1000.0)
    writeFile(orchestratorPidPath(tmp), stalePidFile.toJson())

    # Should succeed because the PID is dead.
    acquireOrchestratorPidGuard(tmp)
    defer: releaseOrchestratorPidGuard(tmp)

    let raw = readFile(orchestratorPidPath(tmp))
    let parsed = fromJson(raw, OrchestratorPidFile)
    check parsed.pid == getCurrentProcessId()

  test "same PID as current process is treated as stale":
    let tmp = createTempDir("pid_guard_same_pid_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    # Our own PID in the guard file means a previous container reused our PID
    # namespace slot. The guard should detect this and overwrite, not error.
    let stalePidFile = OrchestratorPidFile(pid: getCurrentProcessId(), timestamp: 1000.0)
    writeFile(orchestratorPidPath(tmp), stalePidFile.toJson())

    acquireOrchestratorPidGuard(tmp)
    let raw = readFile(orchestratorPidPath(tmp))
    let parsed = fromJson(raw, OrchestratorPidFile)
    check parsed.pid == getCurrentProcessId()
    check parsed.timestamp > 1000.0

  test "alive non-scriptorium PID is treated as stale":
    let tmp = createTempDir("pid_guard_non_script_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    # PID 1 (init) is alive but not scriptorium — cross-container PID collision.
    let stalePidFile = OrchestratorPidFile(pid: 1, timestamp: 1000.0)
    writeFile(orchestratorPidPath(tmp), stalePidFile.toJson())

    acquireOrchestratorPidGuard(tmp)
    let raw = readFile(orchestratorPidPath(tmp))
    let parsed = fromJson(raw, OrchestratorPidFile)
    check parsed.pid == getCurrentProcessId()

  test "creates .scriptorium directory if missing":
    let tmp = createTempDir("pid_guard_mkdir_", "", getTempDir())
    defer: removeDir(tmp)

    acquireOrchestratorPidGuard(tmp)
    defer: releaseOrchestratorPidGuard(tmp)

    check dirExists(tmp / ManagedStateDirName)
    check fileExists(orchestratorPidPath(tmp))

suite "cleanStaleGitLocks static locks":
  test "stale index.lock is removed":
    let tmp = createTempDir("stale_lock_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ".git")
    let lockPath = tmp / ".git" / "index.lock"
    writeFile(lockPath, "")
    let staleTime = getTime() - initDuration(seconds = 600)
    setLastModificationTime(lockPath, staleTime)

    cleanStaleGitLocks(tmp)
    check not fileExists(lockPath)

  test "fresh index.lock is preserved":
    let tmp = createTempDir("fresh_lock_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ".git")
    let lockPath = tmp / ".git" / "index.lock"
    writeFile(lockPath, "")

    cleanStaleGitLocks(tmp)
    check fileExists(lockPath)

  test "stale packed-refs.lock is removed":
    let tmp = createTempDir("stale_packed_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ".git")
    let lockPath = tmp / ".git" / "packed-refs.lock"
    writeFile(lockPath, "")
    let staleTime = getTime() - initDuration(seconds = 600)
    setLastModificationTime(lockPath, staleTime)

    cleanStaleGitLocks(tmp)
    check not fileExists(lockPath)

suite "waitForWorktreeIndexLock":
  test "returns immediately when lock file does not exist":
    let tmp = createTempDir("wt_nolock_", "", getTempDir())
    defer: removeDir(tmp)
    let lockPath = tmp / "index.lock"
    waitForWorktreeIndexLock(lockPath)
    # No exception means success.

  test "raises IOError when lock persists beyond max retries":
    let tmp = createTempDir("wt_persist_", "", getTempDir())
    defer: removeDir(tmp)
    let lockPath = tmp / "index.lock"
    writeFile(lockPath, "")
    var raised = false
    try:
      waitForWorktreeIndexLock(lockPath)
    except IOError:
      raised = true
      check "timed out" in getCurrentExceptionMsg()
      check lockPath in getCurrentExceptionMsg()
    check raised

suite "cleanStaleGitLocks worktree locks":
  test "stale worktree index.lock is removed":
    let tmp = createTempDir("wt_stale_", "", getTempDir())
    defer: removeDir(tmp)
    let wtDir = tmp / ".git" / "worktrees" / "my-worktree"
    createDir(wtDir)
    let lockPath = wtDir / "index.lock"
    writeFile(lockPath, "")
    let staleTime = getTime() - initDuration(seconds = 600)
    setLastModificationTime(lockPath, staleTime)

    cleanStaleGitLocks(tmp)
    check not fileExists(lockPath)

  test "fresh worktree index.lock is preserved":
    let tmp = createTempDir("wt_fresh_", "", getTempDir())
    defer: removeDir(tmp)
    let wtDir = tmp / ".git" / "worktrees" / "my-worktree"
    createDir(wtDir)
    let lockPath = wtDir / "index.lock"
    writeFile(lockPath, "")

    cleanStaleGitLocks(tmp)
    check fileExists(lockPath)

  test "multiple stale worktree locks are all cleaned":
    let tmp = createTempDir("wt_multi_", "", getTempDir())
    defer: removeDir(tmp)
    let staleTime = getTime() - initDuration(seconds = 600)
    var lockPaths: seq[string]
    for name in ["wt-alpha", "wt-beta", "wt-gamma"]:
      let wtDir = tmp / ".git" / "worktrees" / name
      createDir(wtDir)
      let lockPath = wtDir / "index.lock"
      writeFile(lockPath, "")
      setLastModificationTime(lockPath, staleTime)
      lockPaths.add(lockPath)

    cleanStaleGitLocks(tmp)
    for lp in lockPaths:
      check not fileExists(lp)

suite "commit lock":
  test "acquiring commit lock writes correct JSON payload":
    let tmp = createTempDir("commit_lock_write_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    var lockContent = ""
    discard withCommitLock[int](tmp, proc(): int =
      # Lock file should exist during the operation.
      let lp = commitLockPath(tmp)
      check fileExists(lp)
      lockContent = readFile(lp)
      result = 42
    )
    # Verify the payload that was written.
    let parsed = fromJson(lockContent, CommitLockFile)
    check parsed.pid == getCurrentProcessId()
    check parsed.timestamp > 0.0

  test "lock is deleted on normal release":
    let tmp = createTempDir("commit_lock_release_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    discard withCommitLock[int](tmp, proc(): int =
      result = 0
    )
    check not fileExists(commitLockPath(tmp))

  test "lock is deleted when operation raises":
    let tmp = createTempDir("commit_lock_exc_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    var raised = false
    try:
      discard withCommitLock[int](tmp, proc(): int =
        raise newException(ValueError, "boom")
      )
    except ValueError:
      raised = true
    check raised
    check not fileExists(commitLockPath(tmp))

  test "stale lock is stolen with warning":
    let tmp = createTempDir("commit_lock_stale_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    # Write a lock file with a timestamp older than the staleness threshold.
    let staleTimestamp = epochTime() - float(CommitLockStalenessSeconds) - 10.0
    let staleLock = CommitLockFile(pid: 999999, timestamp: staleTimestamp)
    writeFile(commitLockPath(tmp), staleLock.toJson())

    # withCommitLock should steal the stale lock and succeed.
    var executed = false
    discard withCommitLock[int](tmp, proc(): int =
      executed = true
      result = 0
    )
    check executed
    check not fileExists(commitLockPath(tmp))

  test "fresh lock causes retry and eventual timeout":
    let tmp = createTempDir("commit_lock_timeout_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    # Write a fresh lock that will not be stale during the retry window.
    let freshLock = CommitLockFile(pid: getCurrentProcessId(), timestamp: epochTime())
    writeFile(commitLockPath(tmp), freshLock.toJson())

    # Override constants are not possible, but the lock stays fresh so all
    # retries will be exhausted. We use a small subset to keep the test fast.
    # Since we cannot change the constants, we just verify the timeout raises.
    var raised = false
    try:
      discard withCommitLock[int](tmp, proc(): int =
        result = 0
      )
    except IOError:
      raised = true
      check "timed out" in getCurrentExceptionMsg()
    check raised

    # Clean up the lock file we created.
    removeFile(commitLockPath(tmp))

  test "successful acquisition after lock is released during retry window":
    let tmp = createTempDir("commit_lock_retry_ok_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    # Write a lock that is almost stale — it will become stale during retries.
    let almostStaleTimestamp = epochTime() - float(CommitLockStalenessSeconds) + 0.5
    let almostStaleLock = CommitLockFile(pid: 999999, timestamp: almostStaleTimestamp)
    writeFile(commitLockPath(tmp), almostStaleLock.toJson())

    # withCommitLock should retry, detect staleness, steal, and succeed.
    var executed = false
    discard withCommitLock[int](tmp, proc(): int =
      executed = true
      result = 0
    )
    check executed
    check not fileExists(commitLockPath(tmp))
