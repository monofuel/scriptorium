## Tests for logging, stall retry, and duration formatting.

import
  std/[json, os, osproc, sequtils, strformat, strutils, tables, tempfiles, times, unittest],
  scriptorium/[agent_runner, config, init, logging, orchestrator, ticket_metadata],
  helpers

suite "logging":
  test "initLog creates directory and file":
    let tmpDir = createTempDir("scriptorium_log_test_", "")
    defer: removeDir(tmpDir)
    let fakeRepo = tmpDir / "myproject"
    createDir(fakeRepo)
    initLog(fakeRepo)
    defer: closeLog()
    check logFilePath.len > 0
    check fileExists(logFilePath)
    check ".scriptorium/logs/orchestrator/" in logFilePath
    check "run_" in logFilePath

  test "logInfo writes timestamped line to file":
    let tmpDir = createTempDir("scriptorium_log_test_", "")
    defer: removeDir(tmpDir)
    let fakeRepo = tmpDir / "testproj"
    createDir(fakeRepo)
    initLog(fakeRepo)
    logInfo("hello from test")
    closeLog()
    let content = readFile(logFilePath)
    check "[INFO]" in content
    check "hello from test" in content

  test "log levels write correct labels":
    let tmpDir = createTempDir("scriptorium_log_test_", "")
    defer: removeDir(tmpDir)
    let fakeRepo = tmpDir / "leveltest"
    createDir(fakeRepo)
    initLog(fakeRepo)
    logDebug("dbg msg")
    logWarn("wrn msg")
    logError("err msg")
    closeLog()
    let content = readFile(logFilePath)
    check "[DEBUG] dbg msg" in content
    check "[WARN] wrn msg" in content
    check "[ERROR] err msg" in content

  test "log without initLog does not crash":
    closeLog()
    logInfo("should just echo, not crash")

  test "executeAssignedTicket reopens ticket when agent does not call submit_pr":
    let tmp = getTempDir() / "scriptorium_test_reopen_failed"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0032-fail.md", "# Ticket 32\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 900)

    let assignment = assignOldestOpenTicket(tmp)
    let before = planCommitCount(tmp)

    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Simulate an agent that exits 137 without calling submit_pr.
      discard request
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 137,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        lastMessage: "",
        timeoutKind: "hard",
      )

    let runResult = executeAssignedTicket(tmp, assignment, fakeRunner)
    check runResult.exitCode == 137

    let after = planCommitCount(tmp)
    check after == before + 4

    let files = planTreeFiles(tmp)
    check "tickets/open/0032-fail.md" in files
    check "tickets/in-progress/0032-fail.md" notin files

    let commits = latestPlanCommits(tmp, 2)
    check commits[1].startsWith("scriptorium: reopen failed ticket")

  test "executeAssignedTicket retries stalled agent with continuation prompt":
    let tmp = getTempDir() / "scriptorium_test_stall_retry"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0033-stall.md", "# Ticket 33\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 902)

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "Makefile", "test:\n\t@echo OK\nintegration-test:\n\t@echo OK\n")

    var callCount = 0
    var capturedRequests: seq[AgentRunRequest]
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Return stall on first call, then call submit_pr on second call.
      inc callCount
      capturedRequests.add(request)
      if callCount == 2:
        callSubmitPrTool("stall retry done")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: callCount,
        attemptCount: 1,
        stdout: "",
        lastMessage: "done",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunner)

    check callCount == 2
    check capturedRequests.len == 2
    let firstPrompt = capturedRequests[0].prompt
    let retryPrompt = capturedRequests[1].prompt
    check "Ticket 33" in firstPrompt
    check "stall retry" in retryPrompt.toLower
    check "Ticket 33" in retryPrompt
    check "submit_pr" in retryPrompt

  test "executeAssignedTicket stops stall retries after maxAttempts":
    let tmp = getTempDir() / "scriptorium_test_stall_exhausted"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0034-stall.md", "# Ticket 34\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 903)

    let assignment = assignOldestOpenTicket(tmp)
    let before = planCommitCount(tmp)

    var callCount = 0
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Always stall: exit cleanly without calling submit_pr.
      discard request
      inc callCount
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: callCount,
        attemptCount: 1,
        stdout: "",
        lastMessage: "",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunner)
    let after = planCommitCount(tmp)

    check callCount == 2
    let files = planTreeFiles(tmp)
    check "tickets/open/0034-stall.md" in files
    check "tickets/in-progress/0034-stall.md" notin files
    let commits = latestPlanCommits(tmp, 2)
    check commits[1].startsWith("scriptorium: reopen failed ticket")
    check after == before + 5

  test "executeAssignedTicket includes passing test status in stall continuation prompt":
    let tmp = getTempDir() / "scriptorium_test_stall_testpass"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0035-stall.md", "# Ticket 35\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 904)

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "Makefile", "test:\n\t@echo PASS\nintegration-test:\n\t@echo PASS\n")

    var callCount = 0
    var capturedRequests: seq[AgentRunRequest]
    proc fakeRunnerPass(request: AgentRunRequest): AgentRunResult =
      ## Stall on first call, then submit_pr on second.
      inc callCount
      capturedRequests.add(request)
      if callCount == 2:
        callSubmitPrTool("test pass retry done")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: callCount,
        attemptCount: 1,
        stdout: "",
        lastMessage: "done",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunnerPass)

    check callCount == 2
    check capturedRequests.len == 2
    let retryPrompt = capturedRequests[1].prompt
    check "tests are passing" in retryPrompt.toLower
    check "submit_pr" in retryPrompt

  test "executeAssignedTicket includes failing test output in stall continuation prompt":
    let tmp = getTempDir() / "scriptorium_test_stall_testfail"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0036-stall.md", "# Ticket 36\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 905)

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "Makefile", "test:\n\t@echo FAILURE OUTPUT\n\t@false\nintegration-test:\n\t@echo OK\n")

    var callCount = 0
    var capturedRequests: seq[AgentRunRequest]
    proc fakeRunnerFail(request: AgentRunRequest): AgentRunResult =
      ## Stall on first call, then submit_pr on second.
      inc callCount
      capturedRequests.add(request)
      if callCount == 2:
        callSubmitPrTool("test fail retry done")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: callCount,
        attemptCount: 1,
        stdout: "",
        lastMessage: "done",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunnerFail)

    check callCount == 2
    check capturedRequests.len == 2
    let retryPrompt = capturedRequests[1].prompt
    check "tests are failing" in retryPrompt.toLower
    check "FAILURE OUTPUT" in retryPrompt
    check "fix the failing tests" in retryPrompt.toLower

  test "executeAssignedTicket accumulates test wall time on stall":
    let tmp = getTempDir() / "scriptorium_test_stall_testwall"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0037-testwall.md", "# Ticket 37\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 906)

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "Makefile", "test:\n\t@echo OK\nintegration-test:\n\t@echo OK\n")

    let ticketId = "0037"

    var callCount = 0
    proc fakeRunnerStall(request: AgentRunRequest): AgentRunResult =
      ## Stall on first call, then submit_pr on second.
      inc callCount
      if callCount == 2:
        callSubmitPrTool("testwall done")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: callCount,
        attemptCount: 1,
        stdout: "",
        lastMessage: "done",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunnerStall)

    check callCount == 2
    check ticketTestWalls.hasKey(ticketId)
    check ticketTestWalls[ticketId] > 0.0
    check ticketCodingWalls.hasKey(ticketId)
    check ticketCodingWalls[ticketId] >= 0.0
    check ticketStartTimes.hasKey(ticketId)

  test "executeAssignedTicket cleans up timing state on reopen":
    let tmp = getTempDir() / "scriptorium_test_timing_cleanup"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0038-cleanup.md", "# Ticket 38\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 907)

    let assignment = assignOldestOpenTicket(tmp)
    let ticketId = "0038"

    check ticketStartTimes.hasKey(ticketId)
    check ticketCodingWalls.hasKey(ticketId)
    check ticketTestWalls.hasKey(ticketId)

    proc fakeRunnerFail(request: AgentRunRequest): AgentRunResult =
      ## Exit non-zero without submit_pr to trigger reopen.
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 1,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        lastMessage: "",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunnerFail)

    check not ticketStartTimes.hasKey(ticketId)
    check not ticketAttemptCounts.hasKey(ticketId)
    check not ticketCodingWalls.hasKey(ticketId)
    check not ticketTestWalls.hasKey(ticketId)

  test "reassigned ticket gets a fresh worktree branch without stale commits":
    let tmp = getTempDir() / "scriptorium_test_fresh_worktree"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0050-stale.md", "# Ticket 50\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 901)

    let assignment1 = assignOldestOpenTicket(tmp)

    proc fakeRunnerFirst(request: AgentRunRequest): AgentRunResult =
      ## Write a stale file and commit it, then exit non-zero without submit_pr.
      writeFile(request.workingDir / "stale.txt", "should not survive")
      discard execCmdEx("git -C " & quoteShell(request.workingDir) & " add stale.txt")
      discard execCmdEx("git -C " & quoteShell(request.workingDir) & " commit -m stale-commit")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 1,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        lastMessage: "",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment1, fakeRunnerFirst)

    let assignment2 = assignOldestOpenTicket(tmp)
    check assignment2.inProgressTicket.len > 0

    let (logOutput, logRc) = execCmdEx(
      "git -C " & quoteShell(assignment2.worktree) & " log --oneline"
    )
    check logRc == 0
    check "stale-commit" notin logOutput
    check not fileExists(assignment2.worktree / "stale.txt")

    discard execCmdEx("git -C " & quoteShell(tmp) & " worktree remove --force " & quoteShell(assignment2.worktree))

suite "formatDuration":
  test "seconds only":
    check formatDuration(0.0) == "0s"
    check formatDuration(5.0) == "5s"
    check formatDuration(59.9) == "59s"

  test "minutes and seconds":
    check formatDuration(60.0) == "1m0s"
    check formatDuration(192.0) == "3m12s"
    check formatDuration(3599.0) == "59m59s"

  test "hours and minutes":
    check formatDuration(3600.0) == "1h0m"
    check formatDuration(4980.0) == "1h23m"
    check formatDuration(7200.0) == "2h0m"

suite "session summary":
  test "logSessionSummary writes two INFO lines with session stats":
    let tmpDir = createTempDir("scriptorium_session_summary_", "")
    defer: removeDir(tmpDir)
    let fakeRepo = tmpDir / "summarytest"
    createDir(fakeRepo)
    initLog(fakeRepo)

    resetSessionStats()
    sessionStats.totalTicks = 47
    sessionStats.ticketsCompleted = 3
    sessionStats.ticketsReopened = 1
    sessionStats.ticketsParked = 0
    sessionStats.mergeQueueProcessed = 3
    sessionStats.firstAttemptSuccessCount = 2
    sessionStats.completedTicketWalls = @[312.0, 280.0, 345.0]
    sessionStats.completedCodingWalls = @[242.0, 220.0, 265.0]
    sessionStats.completedTestWalls = @[38.0, 42.0, 34.0]
    logSessionSummary()
    closeLog()

    let content = readFile(logFilePath)
    check "session summary: uptime=" in content
    check "ticks=47" in content
    check "tickets_completed=3" in content
    check "tickets_reopened=1" in content
    check "tickets_parked=0" in content
    check "merge_queue_processed=3" in content
    check "session summary: avg_ticket_wall=" in content
    check "avg_coding_wall=" in content
    check "avg_test_wall=" in content
    check "first_attempt_success=66%" in content

  test "logSessionSummary shows n/a when no tickets completed":
    let tmpDir = createTempDir("scriptorium_session_summary_empty_", "")
    defer: removeDir(tmpDir)
    let fakeRepo = tmpDir / "emptytest"
    createDir(fakeRepo)
    initLog(fakeRepo)

    resetSessionStats()
    sessionStats.totalTicks = 5
    logSessionSummary()
    closeLog()

    let content = readFile(logFilePath)
    check "ticks=5" in content
    check "tickets_completed=0" in content
    check "avg_ticket_wall=n/a" in content
    check "avg_coding_wall=n/a" in content
    check "avg_test_wall=n/a" in content
    check "first_attempt_success=0" in content
