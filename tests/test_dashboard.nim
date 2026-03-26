## Tests for the dashboard status JSON construction helpers.

import
  std/[json, options, os, posix, strutils, tempfiles, unittest],
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

suite "parseTitleFromTicketContent":
  test "extracts title from first heading":
    let content = "# My Ticket Title\n\n**Area:** dashboard\n\nSome body."
    check parseTitleFromTicketContent(content) == "My Ticket Title"

  test "returns empty string when no heading":
    check parseTitleFromTicketContent("No heading here\njust text") == ""

  test "ignores sub-headings and finds first h1":
    let content = "## Sub heading\n# Real Title"
    check parseTitleFromTicketContent(content) == "Real Title"

  test "strips extra whitespace from title":
    check parseTitleFromTicketContent("#   Spaced Title  ") == "Spaced Title"

suite "parseTicketSummary":
  test "extracts id, area, title, and state":
    let content = "# Add Foo Feature\n\n**Area:** dashboard\n\nDescription."
    let summary = parseTicketSummary("0042-add-foo.md", content, "open")
    check summary.id == "0042"
    check summary.area == "dashboard"
    check summary.title == "Add Foo Feature"
    check summary.state == "open"

  test "handles ticket with no area field":
    let content = "# No Area Ticket\n\nJust content."
    let summary = parseTicketSummary("0001-no-area.md", content, "done")
    check summary.id == "0001"
    check summary.area == ""
    check summary.title == "No Area Ticket"
    check summary.state == "done"

  test "uses ticketIdFromTicketPath for ID extraction":
    let content = "# Test\n\n**Area:** core"
    let summary = parseTicketSummary("0100-long-slug-name.md", content, "in-progress")
    check summary.id == "0100"

suite "parseQueueItemSummary":
  test "parses all fields from merge queue markdown":
    let content = "# Merge Queue Item\n\n" &
      "**Ticket:** tickets/in-progress/0042-add-foo.md\n" &
      "**Ticket ID:** 0042\n" &
      "**Branch:** scriptorium/ticket-0042\n" &
      "**Worktree:** /tmp/worktree-0042\n" &
      "**Summary:** Add foo feature\n"
    let item = parseQueueItemSummary(content)
    check item.ticketId == "0042"
    check item.branch == "scriptorium/ticket-0042"
    check item.summary == "Add foo feature"

  test "handles missing fields gracefully":
    let content = "# Merge Queue Item\n\n**Ticket ID:** 0099\n"
    let item = parseQueueItemSummary(content)
    check item.ticketId == "0099"
    check item.branch == ""
    check item.summary == ""

  test "handles empty content":
    let item = parseQueueItemSummary("")
    check item.ticketId == ""
    check item.branch == ""
    check item.summary == ""

suite "parseMergeOutcome":
  test "parses success outcome":
    let content = "# Ticket\n\n## Merge Queue Success\n- Summary: Added new feature\n\n## Post-Analysis\n"
    let outcome = parseMergeOutcome(content, "0042")
    check outcome.isSome
    check outcome.get.ticketId == "0042"
    check outcome.get.outcome == "success"
    check outcome.get.summary == "Added new feature"

  test "parses failure outcome":
    let content = "# Ticket\n\n## Merge Queue Failure\n- Summary: Fix bug\n- Failed gate: make test\n"
    let outcome = parseMergeOutcome(content, "0050")
    check outcome.isSome
    check outcome.get.ticketId == "0050"
    check outcome.get.outcome == "failure"
    check outcome.get.summary == "Fix bug"

  test "returns none when no merge section":
    let content = "# Ticket\n\n## Description\nJust a ticket.\n"
    let outcome = parseMergeOutcome(content, "0001")
    check outcome.isNone

  test "stops at next heading after merge section":
    let content = "# Ticket\n\n## Merge Queue Success\n- Summary: Done\n\n## Review\n- Summary: Not this\n"
    let outcome = parseMergeOutcome(content, "0010")
    check outcome.isSome
    check outcome.get.summary == "Done"

suite "parseAgentFromTicket":
  test "parses ticket id, area, and sets role to coder":
    let content = "# Add Login Page\n\n**Area:** auth\n\nDescription here."
    let agent = parseAgentFromTicket("0042-add-login.md", content)
    check agent.ticketId == "0042"
    check agent.areaId == "auth"
    check agent.role == "coder"
    check agent.status == "running"

  test "handles ticket with no area":
    let content = "# Fix Bug\n\nNo area field."
    let agent = parseAgentFromTicket("0099-fix-bug.md", content)
    check agent.ticketId == "0099"
    check agent.areaId == ""
    check agent.role == "coder"
    check agent.status == "running"

  test "elapsed is empty when worktree does not exist":
    let content = "# Task\n\n**Area:** core\n\n**Worktree:** /tmp/nonexistent-worktree-path-12345"
    let agent = parseAgentFromTicket("0001-task.md", content)
    check agent.elapsed == ""

  test "serializes to JSON with expected fields":
    let content = "# Feature\n\n**Area:** dashboard"
    let agent = parseAgentFromTicket("0050-feature.md", content)
    let json = toJson(agent)
    check "role" in json
    check "ticketId" in json
    check "areaId" in json
    check "elapsed" in json
    check "status" in json
    check "\"coder\"" in json
    check "\"running\"" in json

suite "parseAreaSummary":
  test "extracts id and first line as summary":
    let content = "# Dashboard Area\n\nThis area covers the web dashboard."
    let area = parseAreaSummary("dashboard.md", content)
    check area.id == "dashboard"
    check area.summary == "# Dashboard Area"

  test "strips .md extension from filename for id":
    let area = parseAreaSummary("core-engine.md", "Core engine overview")
    check area.id == "core-engine"

  test "skips empty leading lines":
    let content = "\n\n  \nActual first line"
    let area = parseAreaSummary("test.md", content)
    check area.summary == "Actual first line"

  test "returns empty summary for empty content":
    let area = parseAreaSummary("empty.md", "")
    check area.id == "empty"
    check area.summary == ""

  test "returns empty summary for whitespace-only content":
    let area = parseAreaSummary("blank.md", "  \n  \n  ")
    check area.id == "blank"
    check area.summary == ""

  test "serializes to JSON with expected fields":
    let area = parseAreaSummary("auth.md", "# Authentication\n\nHandles auth.")
    let json = toJson(area)
    check "\"id\"" in json
    check "\"summary\"" in json
    check "\"auth\"" in json
    check "\"# Authentication\"" in json

suite "resolveLogDir":
  test "builds correct path for coder role":
    let path = resolveLogDir("/repo", "coder", "0042")
    check path == "/repo/.scriptorium/logs/coder/0042"

  test "builds correct path for review role":
    let path = resolveLogDir("/repo", "review", "0099")
    check path == "/repo/.scriptorium/logs/review/0099"

  test "builds correct path for architect role":
    let path = resolveLogDir("/repo", "architect", "spec")
    check path == "/repo/.scriptorium/logs/architect/spec"

suite "getLogContent":
  test "returns none when log directory does not exist":
    let tmp = createTempDir("logs_missing_", "", getTempDir())
    defer: removeDir(tmp)
    let result = getLogContent(tmp, "coder", "0042")
    check result.isNone

  test "returns content when jsonl file exists":
    let tmp = createTempDir("logs_exist_", "", getTempDir())
    defer: removeDir(tmp)
    let logDir = tmp / ".scriptorium" / "logs" / "coder" / "0042"
    createDir(logDir)
    writeFile(logDir / "attempt-01.jsonl", "{\"msg\":\"hello\"}")
    let result = getLogContent(tmp, "coder", "0042")
    check result.isSome
    check result.get.role == "coder"
    check result.get.id == "0042"
    check "{\"msg\":\"hello\"}" in result.get.content

  test "returns none when directory exists but is empty":
    let tmp = createTempDir("logs_empty_", "", getTempDir())
    defer: removeDir(tmp)
    let logDir = tmp / ".scriptorium" / "logs" / "review" / "0001"
    createDir(logDir)
    let result = getLogContent(tmp, "review", "0001")
    check result.isNone

  test "falls back to non-jsonl files when no jsonl present":
    let tmp = createTempDir("logs_txt_", "", getTempDir())
    defer: removeDir(tmp)
    let logDir = tmp / ".scriptorium" / "logs" / "architect" / "spec"
    createDir(logDir)
    writeFile(logDir / "stdout.log", "some output")
    let result = getLogContent(tmp, "architect", "spec")
    check result.isSome
    check "some output" in result.get.content

suite "ValidLogRoles":
  test "contains expected roles":
    check "coder" in ValidLogRoles
    check "manager" in ValidLogRoles
    check "review" in ValidLogRoles
    check "architect" in ValidLogRoles
    check "audit" in ValidLogRoles

  test "rejects unknown roles":
    check "unknown" notin ValidLogRoles
    check "admin" notin ValidLogRoles

suite "parseHealthCache":
  test "returns defaults for empty JSON object":
    let result = parseHealthCache("{}")
    check result.lastCommit.isNone
    check result.healthy == false
    check result.timestamp.isNone

  test "returns single entry":
    let raw = """{"abc123": {"healthy": true, "timestamp": "2026-03-25T10:00:00Z", "test_exit_code": 0, "integration_test_exit_code": 0, "test_wall_seconds": 10, "integration_test_wall_seconds": 20}}"""
    let result = parseHealthCache(raw)
    check result.lastCommit.isSome
    check result.lastCommit.get == "abc123"
    check result.healthy == true
    check result.timestamp.isSome
    check result.timestamp.get == "2026-03-25T10:00:00Z"

  test "returns entry with latest timestamp":
    let raw = """{
      "older": {"healthy": false, "timestamp": "2026-03-24T08:00:00Z", "test_exit_code": 1, "integration_test_exit_code": 0, "test_wall_seconds": 5, "integration_test_wall_seconds": 10},
      "newer": {"healthy": true, "timestamp": "2026-03-25T12:00:00Z", "test_exit_code": 0, "integration_test_exit_code": 0, "test_wall_seconds": 8, "integration_test_wall_seconds": 15}
    }"""
    let result = parseHealthCache(raw)
    check result.lastCommit.get == "newer"
    check result.healthy == true
    check result.timestamp.get == "2026-03-25T12:00:00Z"

  test "returns unhealthy entry when it is latest":
    let raw = """{
      "good": {"healthy": true, "timestamp": "2026-03-20T00:00:00Z", "test_exit_code": 0, "integration_test_exit_code": 0, "test_wall_seconds": 5, "integration_test_wall_seconds": 10},
      "bad": {"healthy": false, "timestamp": "2026-03-26T00:00:00Z", "test_exit_code": 1, "integration_test_exit_code": 0, "test_wall_seconds": 5, "integration_test_wall_seconds": 10}
    }"""
    let result = parseHealthCache(raw)
    check result.lastCommit.get == "bad"
    check result.healthy == false

  test "serializes to JSON with expected fields":
    let result = parseHealthCache("{}")
    let jsonStr = toJson(result)
    check "lastCommit" in jsonStr
    check "healthy" in jsonStr
    check "timestamp" in jsonStr

suite "IterationResponse serialization":
  test "serializes with expected fields":
    let resp = IterationResponse(currentIteration: 3, logContent: "## Iteration 3\nContent")
    let jsonStr = toJson(resp)
    check "currentIteration" in jsonStr
    check "logContent" in jsonStr
    check "3" in jsonStr

suite "PauseResponse serialization":
  test "paused true serializes correctly":
    let resp = PauseResponse(paused: true)
    let jsonStr = toJson(resp)
    check "\"paused\":true" in jsonStr

  test "paused false serializes correctly":
    let resp = PauseResponse(paused: false)
    let jsonStr = toJson(resp)
    check "\"paused\":false" in jsonStr

suite "pause and resume toggle":
  test "pause creates flag and resume removes it":
    let tmp = createTempDir("dashboard_pause_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    check isPaused(tmp) == false

    writePauseFlag(tmp)
    check isPaused(tmp) == true

    removePauseFlag(tmp)
    check isPaused(tmp) == false

  test "pause is idempotent":
    let tmp = createTempDir("dashboard_pause_idem_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    writePauseFlag(tmp)
    writePauseFlag(tmp)
    check isPaused(tmp) == true

  test "resume is idempotent":
    let tmp = createTempDir("dashboard_resume_idem_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    removePauseFlag(tmp)
    check isPaused(tmp) == false

  test "pause then resume then pause toggles correctly":
    let tmp = createTempDir("dashboard_toggle_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    writePauseFlag(tmp)
    check isPaused(tmp) == true

    removePauseFlag(tmp)
    check isPaused(tmp) == false

    writePauseFlag(tmp)
    check isPaused(tmp) == true
