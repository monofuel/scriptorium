## Tests for the dashboard status JSON construction helpers.

import
  std/[options, os, posix, strutils, tempfiles, unittest],
  jsony,
  scriptorium/[dashboard, git_ops, pause_flag]

suite "formatUptime":
  test "seconds only":
    check formatUptime(42) == "42s"

  test "minutes and seconds":
    check formatUptime(125) == "2m 5s"

  test "hours, minutes and seconds":
    check formatUptime(3661) == "1h 1m 1s"

  test "days, hours, minutes and seconds":
    check formatUptime(90061) == "1d 1h 1m 1s"

  test "zero seconds":
    check formatUptime(0) == "0s"

suite "parseIterationCount":
  test "empty string returns 0":
    check parseIterationCount("") == 0

  test "single iteration heading":
    check parseIterationCount("## Iteration 1\nsome content") == 1

  test "multiple iteration headings returns highest":
    let content = "## Iteration 1\nfoo\n## Iteration 3\nbar\n## Iteration 2\nbaz"
    check parseIterationCount(content) == 3

  test "no matching headings returns 0":
    check parseIterationCount("# Not an iteration\nrandom text") == 0

  test "malformed number is skipped":
    check parseIterationCount("## Iteration abc\n## Iteration 5") == 5

suite "getApiStatus":
  test "no PID file and no pause returns defaults":
    let tmp = createTempDir("dashboard_status_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    let status = getApiStatus(tmp)
    check status.pidAlive == false
    check status.uptime.isNone
    check status.paused == false
    check status.loopIteration == 0

  test "paused flag is detected":
    let tmp = createTempDir("dashboard_paused_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)
    writePauseFlag(tmp)

    let status = getApiStatus(tmp)
    check status.paused == true

  test "PID of current process is detected as alive":
    let tmp = createTempDir("dashboard_pid_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    let pid = getpid()
    writeFile(orchestratorPidPath(tmp), $pid)

    let status = getApiStatus(tmp)
    check status.pidAlive == true
    check status.uptime.isSome

  test "PID of non-existent process is not alive":
    let tmp = createTempDir("dashboard_deadpid_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    # Use a very high PID that almost certainly does not exist.
    writeFile(orchestratorPidPath(tmp), "999999999")

    let status = getApiStatus(tmp)
    check status.pidAlive == false
    check status.uptime.isNone

  test "status serializes to JSON with expected fields":
    let tmp = createTempDir("dashboard_json_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    let status = getApiStatus(tmp)
    let json = toJson(status)
    check "pidAlive" in json
    check "uptime" in json
    check "paused" in json
    check "loopIteration" in json
