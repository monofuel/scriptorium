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
