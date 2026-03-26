## Tests for the dashboard status JSON construction helpers and HTML view rendering.

import
  std/[json, options, os, posix, sequtils, strutils, tempfiles, unittest],
  jsony,
  scriptorium/[dashboard, dashboard_views, git_ops, pause_flag]

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

suite "oobFragment":
  test "generates correct htmx out-of-band swap div":
    let result = oobFragment("status", "hello")
    check result == """<div id="status" hx-swap-oob="true">hello</div>"""

  test "handles empty content":
    let result = oobFragment("target", "")
    check result == """<div id="target" hx-swap-oob="true"></div>"""

  test "preserves HTML content inside fragment":
    let inner = "<span>active</span>"
    let result = oobFragment("badge", inner)
    check result == """<div id="badge" hx-swap-oob="true"><span>active</span></div>"""

  test "handles JSON content":
    let jsonContent = """{"pidAlive":true,"paused":false}"""
    let result = oobFragment("status", jsonContent)
    check """hx-swap-oob="true">{"pidAlive":true,"paused":false}</div>""" in result

suite "renderNavigation":
  test "contains all navigation links":
    let nav = renderNavigation("overview")
    check "<nav>" in nav
    check "Overview" in nav
    check "Ticket Board" in nav
    check "Merge Queue" in nav
    check "Agents" in nav
    check "Spec" in nav
    check "Logs" in nav

  test "marks active view with active class":
    let nav = renderNavigation("overview")
    check """class="active">Overview""" in nav

  test "does not mark inactive views as active":
    let nav = renderNavigation("overview")
    check """class="active">Agents""" notin nav

  test "marks different view as active":
    let nav = renderNavigation("tickets")
    check """class="active">Ticket Board""" in nav

suite "renderStatusFragment":
  test "shows running when pid is alive":
    let html = renderStatusFragment(true, some("1h 5m 3s"), false, 10)
    check "Running" in html
    check "status-ok" in html
    check "1h 5m 3s" in html
    check "10" in html

  test "shows stopped when pid is not alive":
    let html = renderStatusFragment(false, none(string), false, 0)
    check "Stopped" in html
    check "status-error" in html

  test "shows paused badge when paused":
    let html = renderStatusFragment(true, some("5s"), true, 1)
    check "PAUSED" in html
    check "badge-yellow" in html

  test "no paused badge when not paused":
    let html = renderStatusFragment(true, some("5s"), false, 1)
    check "PAUSED" notin html

suite "renderTicketsFragment":
  test "shows ticket counts":
    let html = renderTicketsFragment(5, 3, 12)
    check "3" in html
    check "in progress" in html
    check "5 open" in html
    check "12 done" in html

  test "shows zero counts":
    let html = renderTicketsFragment(0, 0, 0)
    check "0" in html

suite "renderAgentsFragment":
  test "shows agent slot usage":
    let html = renderAgentsFragment(2, 4)
    check "2 / 4" in html
    check "agent slots in use" in html

suite "renderQueueFragment":
  test "shows pending count and active status":
    let html = renderQueueFragment(3, true)
    check "3 pending" in html
    check "1 active" in html

  test "shows idle when no active item":
    let html = renderQueueFragment(0, false)
    check "0 pending" in html
    check "idle" in html

suite "renderHealthFragment":
  test "shows healthy status with commit":
    let html = renderHealthFragment(true, true, some("abc1234def"))
    check "Healthy" in html
    check "status-ok" in html
    check "abc1234" in html

  test "shows unhealthy status":
    let html = renderHealthFragment(false, true, some("bad1234"))
    check "Unhealthy" in html
    check "status-error" in html

  test "shows no data when hasData is false":
    let html = renderHealthFragment(false, false, none(string))
    check "No data" in html

suite "renderOverviewSection":
  test "contains all htmx-powered cards with correct ids":
    let html = renderOverviewSection()
    check """id="overview-status"""" in html
    check """id="overview-tickets"""" in html
    check """id="overview-agents"""" in html
    check """id="overview-queue"""" in html
    check """id="overview-health"""" in html

  test "cards use hx-get to load from fragment endpoints":
    let html = renderOverviewSection()
    check """hx-get="/fragments/status"""" in html
    check """hx-get="/fragments/tickets"""" in html
    check """hx-get="/fragments/agents"""" in html
    check """hx-get="/fragments/queue"""" in html
    check """hx-get="/fragments/health"""" in html

  test "cards use hx-trigger load":
    let html = renderOverviewSection()
    check """hx-trigger="load"""" in html

suite "renderOverviewPage":
  test "produces full HTML page with doctype and head":
    let html = renderOverviewPage()
    check "<!DOCTYPE html>" in html
    check "<html>" in html
    check "<title>scriptorium dashboard</title>" in html
    check "<style>" in html

  test "includes htmx script tag":
    let html = renderOverviewPage()
    check "htmx.org" in html

  test "includes websocket extension":
    let html = renderOverviewPage()
    check "htmx-ext-ws" in html
    check """ws-connect="/ws"""" in html

  test "includes navigation with overview active":
    let html = renderOverviewPage()
    check """class="active">Overview""" in html

  test "includes overview section cards":
    let html = renderOverviewPage()
    check """id="overview-status"""" in html

suite "renderPage":
  test "wraps body content with navigation":
    let html = renderPage("agents", "<div>content</div>")
    check "<nav>" in html
    check "<div>content</div>" in html
    check """class="active">Agents""" in html

suite "parseTicketCard":
  test "parses open ticket with no metrics":
    let content = "# Add Foo\n\n**Area:** dashboard\n\nDescription."
    let card = parseTicketCard("0042", "dashboard", "Add Foo", "open", content)
    check card.id == "0042"
    check card.area == "dashboard"
    check card.title == "Add Foo"
    check card.state == "open"
    check card.attempt == ""
    check card.wallTime == ""
    check card.outcome == ""

  test "parses done ticket with metrics":
    let content = "# Fix Bug\n\n**Area:** core\n\n## Metrics\n" &
      "- wall_time_seconds: 120\n- attempt_count: 2\n- outcome: success\n"
    let card = parseTicketCard("0099", "core", "Fix Bug", "done", content)
    check card.attempt == "2"
    check card.wallTime == "120s"
    check card.outcome == "success"

  test "parses in-progress ticket with attempt count":
    let content = "# WIP\n\n## Metrics\n- attempt_count: 3\n"
    let card = parseTicketCard("0010", "", "WIP", "in-progress", content)
    check card.attempt == "3"

  test "stops parsing metrics at next heading":
    let content = "# T\n\n## Metrics\n- attempt_count: 1\n## Other\n- attempt_count: 9\n"
    let card = parseTicketCard("0001", "", "T", "done", content)
    check card.attempt == "1"

suite "renderTicketCard":
  test "renders open card with area badge":
    let card = TicketCard(id: "0042", area: "dashboard", title: "Add Foo", state: "open")
    let html = renderTicketCard(card)
    check "ticket-card" in html
    check "0042" in html
    check "dashboard" in html
    check "badge-blue" in html
    check "Add Foo" in html
    check """hx-get="/api/tickets/0042"""" in html

  test "renders in-progress card with elapsed and attempt":
    let card = TicketCard(id: "0050", area: "core", title: "Fix Bug",
                          state: "in-progress", elapsed: "5m 30s", attempt: "2")
    let html = renderTicketCard(card)
    check "Elapsed: 5m 30s" in html
    check "Attempt: 2" in html

  test "renders done card with outcome and wall time":
    let card = TicketCard(id: "0099", area: "", title: "Done Task",
                          state: "done", outcome: "success", wallTime: "120s")
    let html = renderTicketCard(card)
    check "Outcome: success" in html
    check "Wall: 120s" in html

  test "card without area omits badge":
    let card = TicketCard(id: "0001", area: "", title: "No Area", state: "open")
    let html = renderTicketCard(card)
    check "badge-blue" notin html

  test "card includes expandable detail div":
    let card = TicketCard(id: "0001", area: "", title: "T", state: "open")
    let html = renderTicketCard(card)
    check "ticket-detail" in html

suite "renderTicketBoardSection":
  test "renders three columns":
    let html = renderTicketBoardSection(@[], @[], @[])
    check "kanban" in html
    check ">Open<" in html
    check ">In Progress<" in html
    check ">Done<" in html

  test "includes cards in correct columns":
    let openCard = TicketCard(id: "0001", area: "a", title: "O", state: "open")
    let ipCard = TicketCard(id: "0002", area: "b", title: "I", state: "in-progress")
    let doneCard = TicketCard(id: "0003", area: "c", title: "D", state: "done")
    let html = renderTicketBoardSection(@[openCard], @[ipCard], @[doneCard])
    check "0001" in html
    check "0002" in html
    check "0003" in html

suite "renderQueueItem":
  test "renders pending item without active class":
    let item = QueueViewItem(ticketId: "0042", branch: "scriptorium/ticket-0042",
                             summary: "Add foo feature", isActive: false)
    let html = renderQueueItem(item)
    check "0042" in html
    check "Add foo feature" in html
    check "scriptorium/ticket-0042" in html
    check """class="active"""" notin html

  test "renders active item with highlighted class":
    let item = QueueViewItem(ticketId: "0050", branch: "scriptorium/ticket-0050",
                             summary: "Fix bug", isActive: true)
    let html = renderQueueItem(item)
    check """class="active"""" in html
    check "0050" in html

  test "renders as list item":
    let item = QueueViewItem(ticketId: "0001", branch: "b", summary: "s", isActive: false)
    let html = renderQueueItem(item)
    check html.startsWith("<li")
    check html.endsWith("</li>")

suite "renderMergeHistoryItem":
  test "renders pass indicator for successful merge":
    let item = MergeHistoryItem(ticketId: "0042", passed: true, summary: "Added feature")
    let html = renderMergeHistoryItem(item)
    check "history-pass" in html
    check "&#10003;" in html
    check "0042" in html
    check "Added feature" in html

  test "renders fail indicator for failed merge":
    let item = MergeHistoryItem(ticketId: "0099", passed: false, summary: "Build failed")
    let html = renderMergeHistoryItem(item)
    check "history-fail" in html
    check "&#10007;" in html
    check "0099" in html

suite "renderMergeQueueSection":
  test "renders empty state when no pending items":
    let html = renderMergeQueueSection(@[], @[])
    check "Merge Queue" in html
    check "No pending items" in html

  test "renders ordered list with pending items":
    let items = @[
      QueueViewItem(ticketId: "0001", branch: "b1", summary: "s1", isActive: false),
      QueueViewItem(ticketId: "0002", branch: "b2", summary: "s2", isActive: true),
    ]
    let html = renderMergeQueueSection(items, @[])
    check "queue-list" in html
    check "0001" in html
    check "0002" in html
    check """class="active"""" in html

  test "renders recent history section":
    let history = @[
      MergeHistoryItem(ticketId: "0010", passed: true, summary: "Done"),
      MergeHistoryItem(ticketId: "0011", passed: false, summary: "Failed"),
    ]
    let html = renderMergeQueueSection(@[], history)
    check "Recent History" in html
    check "history-pass" in html
    check "history-fail" in html

  test "omits history section when empty":
    let html = renderMergeQueueSection(@[], @[])
    check "Recent History" notin html

  test "uses hx-get for live loading":
    let html = renderMergeQueueSection(@[], @[])
    check """hx-get="/api/queue"""" in html
    check """hx-trigger="load"""" in html

suite "renderMergeQueuePage":
  test "produces full HTML page with queue view active":
    let html = renderMergeQueuePage(@[], @[])
    check "<!DOCTYPE html>" in html
    check """class="active">Merge Queue""" in html
    check "Merge Queue" in html

suite "renderAgentRow":
  test "renders row with ticket id":
    let slot = AgentViewSlot(role: "coder", ticketId: "0042", areaId: "",
                             elapsed: "5m 30s", status: "running")
    let html = renderAgentRow(slot)
    check "<tr>" in html
    check "coder" in html
    check "0042" in html
    check "5m 30s" in html
    check "running" in html

  test "renders row with area id when no ticket":
    let slot = AgentViewSlot(role: "manager", ticketId: "", areaId: "dashboard",
                             elapsed: "", status: "running")
    let html = renderAgentRow(slot)
    check "manager" in html
    check "dashboard" in html

  test "renders dash when no identifier":
    let slot = AgentViewSlot(role: "coder", ticketId: "", areaId: "",
                             elapsed: "", status: "running")
    let html = renderAgentRow(slot)
    check "<td>-</td>" in html

  test "renders dash for empty elapsed":
    let slot = AgentViewSlot(role: "coder", ticketId: "0001", areaId: "",
                             elapsed: "", status: "running")
    let html = renderAgentRow(slot)
    check ">-</td>" in html

suite "renderAgentsSection":
  test "renders table with headers":
    let html = renderAgentsSection(@[], 4)
    check "agents-table" in html
    check "<th>Role</th>" in html
    check "<th>Ticket/Area</th>" in html
    check "<th>Elapsed</th>" in html
    check "<th>Status</th>" in html

  test "shows empty state when no agents":
    let html = renderAgentsSection(@[], 4)
    check "No active agents" in html

  test "renders agent rows":
    let agents = @[
      AgentViewSlot(role: "coder", ticketId: "0042", areaId: "core",
                    elapsed: "2m 10s", status: "running"),
    ]
    let html = renderAgentsSection(agents, 4)
    check "0042" in html
    check "coder" in html

  test "shows slot usage in footer":
    let agents = @[
      AgentViewSlot(role: "coder", ticketId: "0001", areaId: "",
                    elapsed: "1m", status: "running"),
      AgentViewSlot(role: "coder", ticketId: "0002", areaId: "",
                    elapsed: "3m", status: "running"),
    ]
    let html = renderAgentsSection(agents, 4)
    check "2/4 slots in use" in html

  test "uses hx-get for live loading":
    let html = renderAgentsSection(@[], 4)
    check """hx-get="/api/agents"""" in html
    check """hx-trigger="load"""" in html

suite "renderAgentsPage":
  test "produces full HTML page with agents view active":
    let html = renderAgentsPage(@[], 4)
    check "<!DOCTYPE html>" in html
    check """class="active">Agents""" in html
    check "Agents" in html
