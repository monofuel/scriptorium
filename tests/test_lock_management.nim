## Tests for the orchestrator singleton PID guard in lock_management.

import
  std/[os, posix, strutils, tempfiles, unittest],
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
