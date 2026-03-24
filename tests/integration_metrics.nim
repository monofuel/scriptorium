## Tests for per-ticket metrics, difficulty prediction, health cache, submit_pr state,
## agent slots, token budget tracking, and rate limit backpressure.

import
  std/[json, os, osproc, sequtils, strformat, strutils, tables, tempfiles, times, unittest],
  scriptorium/[agent_runner, config, init, logging, orchestrator, ticket_metadata],
  helpers

suite "parseMetricField":
  const
    SampleTicket = "# Ticket\n\n**Area:** a\n\n## Metrics\n- wall_time_seconds: 120\n- outcome: done\n- attempt_count: 1\n- model: opus\n\n## Post-Analysis\n- actual_difficulty: easy\n"

  test "extracts wall_time_seconds from metrics section":
    check parseMetricField(SampleTicket, "wall_time_seconds") == "120"

  test "extracts outcome from metrics section":
    check parseMetricField(SampleTicket, "outcome") == "done"

  test "extracts attempt_count from metrics section":
    check parseMetricField(SampleTicket, "attempt_count") == "1"

  test "returns empty string when field missing":
    check parseMetricField(SampleTicket, "nonexistent") == ""

  test "returns empty string when no metrics section":
    check parseMetricField("# Ticket\n\nNo metrics here.\n", "outcome") == ""

  test "stops at next section":
    check parseMetricField(SampleTicket, "actual_difficulty") == ""

suite "per-ticket metrics":
  setup:
    ticketStartTimes.clear()
    ticketAttemptCounts.clear()
    ticketCodingWalls.clear()
    ticketTestWalls.clear()
    ticketModels.clear()
    ticketStdoutBytes.clear()

  test "formatMetricsNote includes all required fields for done outcome":
    let ticketId = "0042"
    ticketStartTimes[ticketId] = epochTime() - 120.0
    ticketAttemptCounts[ticketId] = 2
    ticketCodingWalls[ticketId] = 95.0
    ticketTestWalls[ticketId] = 20.0
    ticketModels[ticketId] = "claude-sonnet-4-20250514"
    ticketStdoutBytes[ticketId] = 8192

    let note = formatMetricsNote(ticketId, "done", "")
    check "## Metrics" in note
    check "- wall_time_seconds: 1" in note
    check "- coding_wall_seconds: 95" in note
    check "- test_wall_seconds: 20" in note
    check "- attempt_count: 2" in note
    check "- outcome: done" in note
    check "- failure_reason: " in note
    check "- model: claude-sonnet-4-20250514" in note
    check "- stdout_bytes: 8192" in note

  test "formatMetricsNote includes failure_reason for reopened outcome":
    let ticketId = "0043"
    ticketStartTimes[ticketId] = epochTime() - 60.0
    ticketAttemptCounts[ticketId] = 1
    ticketCodingWalls[ticketId] = 50.0
    ticketTestWalls[ticketId] = 5.0
    ticketModels[ticketId] = "test-model"
    ticketStdoutBytes[ticketId] = 1024

    let note = formatMetricsNote(ticketId, "reopened", "stall")
    check "- outcome: reopened" in note
    check "- failure_reason: stall" in note

  test "formatMetricsNote includes failure_reason for parked outcome":
    let ticketId = "0044"
    ticketStartTimes[ticketId] = epochTime() - 300.0
    ticketAttemptCounts[ticketId] = 3
    ticketCodingWalls[ticketId] = 200.0
    ticketTestWalls[ticketId] = 80.0
    ticketModels[ticketId] = "test-model"
    ticketStdoutBytes[ticketId] = 4096

    let note = formatMetricsNote(ticketId, "parked", "parked")
    check "- outcome: parked" in note
    check "- failure_reason: parked" in note

  test "appendMetricsNote appends metrics section to ticket content":
    let ticketId = "0045"
    ticketStartTimes[ticketId] = epochTime() - 30.0
    ticketAttemptCounts[ticketId] = 1
    ticketCodingWalls[ticketId] = 25.0
    ticketTestWalls[ticketId] = 3.0
    ticketModels[ticketId] = "test-model"
    ticketStdoutBytes[ticketId] = 512

    let content = "# Test Ticket\n\nSome description."
    let updated = appendMetricsNote(content, ticketId, "done", "")
    check updated.startsWith("# Test Ticket")
    check "## Metrics" in updated
    check "- outcome: done" in updated

  test "cleanupTicketTimings removes all state for a ticket":
    let ticketId = "0046"
    ticketStartTimes[ticketId] = epochTime()
    ticketAttemptCounts[ticketId] = 1
    ticketCodingWalls[ticketId] = 10.0
    ticketTestWalls[ticketId] = 5.0
    ticketModels[ticketId] = "test-model"
    ticketStdoutBytes[ticketId] = 100

    cleanupTicketTimings(ticketId)
    check ticketId notin ticketStartTimes
    check ticketId notin ticketAttemptCounts
    check ticketId notin ticketCodingWalls
    check ticketId notin ticketTestWalls
    check ticketId notin ticketModels
    check ticketId notin ticketStdoutBytes

  test "formatMetricsNote uses defaults for missing ticket state":
    let ticketId = "0047"
    let note = formatMetricsNote(ticketId, "reopened", "timeout_hard")
    check "- wall_time_seconds: 0" in note
    check "- coding_wall_seconds: 0" in note
    check "- test_wall_seconds: 0" in note
    check "- attempt_count: 0" in note
    check "- model: unknown" in note
    check "- stdout_bytes: 0" in note
    check "- failure_reason: timeout_hard" in note

suite "ticket difficulty prediction":
  test "parsePredictionResponse parses valid JSON":
    let response = """{"predicted_difficulty": "medium", "predicted_duration_minutes": 30, "reasoning": "Moderate complexity."}"""
    let prediction = parsePredictionResponse(response)
    check prediction.difficulty == "medium"
    check prediction.durationMinutes == 30
    check prediction.reasoning == "Moderate complexity."

  test "parsePredictionResponse handles JSON with surrounding text":
    let response = "Here is my assessment:\n{\"predicted_difficulty\": \"easy\", \"predicted_duration_minutes\": 10, \"reasoning\": \"Simple change.\"}\nDone."
    let prediction = parsePredictionResponse(response)
    check prediction.difficulty == "easy"
    check prediction.durationMinutes == 10

  test "parsePredictionResponse rejects invalid difficulty":
    expect(ValueError):
      discard parsePredictionResponse("""{"predicted_difficulty": "impossible", "predicted_duration_minutes": 5, "reasoning": "test"}""")

  test "parsePredictionResponse rejects missing JSON":
    expect(ValueError):
      discard parsePredictionResponse("no json here")

  test "formatPredictionNote produces expected markdown":
    let prediction = TicketPrediction(
      difficulty: "hard",
      durationMinutes: 45,
      reasoning: "Multiple modules need changes.",
    )
    let note = formatPredictionNote(prediction)
    check "## Prediction" in note
    check "- predicted_difficulty: hard" in note
    check "- predicted_duration_minutes: 45" in note
    check "- reasoning: Multiple modules need changes." in note

  test "appendPredictionNote appends prediction section to ticket content":
    let content = "# Test Ticket\n\nSome description."
    let prediction = TicketPrediction(
      difficulty: "trivial",
      durationMinutes: 5,
      reasoning: "Simple fix.",
    )
    let updated = appendPredictionNote(content, prediction)
    check updated.startsWith("# Test Ticket")
    check "## Prediction" in updated
    check "- predicted_difficulty: trivial" in updated

  test "buildPredictionPrompt renders template with all placeholders":
    let prompt = buildPredictionPrompt("ticket body", "area body", "spec summary")
    check "ticket body" in prompt
    check "area body" in prompt
    check "spec summary" in prompt

  test "parsePredictionFromContent extracts prediction fields":
    let content = "# Ticket\n\n## Prediction\n- predicted_difficulty: medium\n- predicted_duration_minutes: 30\n- reasoning: Moderate.\n"
    let prediction = parsePredictionFromContent(content)
    check prediction.found == true
    check prediction.difficulty == "medium"
    check prediction.durationMinutes == 30

  test "parsePredictionFromContent returns not found when no prediction section":
    let content = "# Ticket\n\nSome description.\n"
    let prediction = parsePredictionFromContent(content)
    check prediction.found == false

  test "parsePredictionFromContent stops at next section":
    let content = "# Ticket\n\n## Prediction\n- predicted_difficulty: easy\n- predicted_duration_minutes: 10\n\n## Metrics\n- wall_time_seconds: 100\n"
    let prediction = parsePredictionFromContent(content)
    check prediction.found == true
    check prediction.difficulty == "easy"
    check prediction.durationMinutes == 10

  test "classifyActualDifficulty returns trivial for quick single attempt done":
    check classifyActualDifficulty(1, "done", 120) == "trivial"

  test "classifyActualDifficulty returns easy for moderate single attempt done":
    check classifyActualDifficulty(1, "done", 600) == "easy"

  test "classifyActualDifficulty returns medium for long single attempt done":
    check classifyActualDifficulty(1, "done", 1200) == "medium"

  test "classifyActualDifficulty returns hard for two attempt done":
    check classifyActualDifficulty(2, "done", 600) == "hard"

  test "classifyActualDifficulty returns complex for many attempts done":
    check classifyActualDifficulty(3, "done", 600) == "complex"

  test "classifyActualDifficulty returns hard for reopened with few attempts":
    check classifyActualDifficulty(1, "reopened", 300) == "hard"

  test "classifyActualDifficulty returns complex for reopened with many attempts":
    check classifyActualDifficulty(3, "reopened", 300) == "complex"

  test "classifyActualDifficulty returns complex for parked":
    check classifyActualDifficulty(1, "parked", 100) == "complex"

  test "compareDifficulty returns accurate for matching levels":
    check compareDifficulty("medium", "medium") == "accurate"

  test "compareDifficulty returns underestimated when predicted easier":
    check compareDifficulty("easy", "hard") == "underestimated"

  test "compareDifficulty returns overestimated when predicted harder":
    check compareDifficulty("complex", "easy") == "overestimated"

  test "formatPostAnalysisNote produces expected markdown":
    let note = formatPostAnalysisNote("medium", "accurate", "Predicted medium, actual was medium.")
    check "## Post-Analysis" in note
    check "- actual_difficulty: medium" in note
    check "- prediction_accuracy: accurate" in note
    check "- brief_summary: Predicted medium, actual was medium." in note

  test "appendPostAnalysisNote appends post-analysis section":
    let content = "# Ticket\n\nDescription."
    let updated = appendPostAnalysisNote(content, "hard", "underestimated", "Was harder than expected.")
    check updated.startsWith("# Ticket")
    check "## Post-Analysis" in updated
    check "- actual_difficulty: hard" in updated

  test "runPostAnalysis generates full analysis for ticket with prediction":
    let content = "# Ticket\n\n## Prediction\n- predicted_difficulty: easy\n- predicted_duration_minutes: 10\n- reasoning: Simple.\n\n## Metrics\n- wall_time_seconds: 1200\n- attempt_count: 2\n- outcome: done\n"
    let updated = runPostAnalysis(content, "0050", "done", 2, 1200)
    check "## Post-Analysis" in updated
    check "- actual_difficulty: hard" in updated
    check "- prediction_accuracy: underestimated" in updated
    check "- brief_summary:" in updated

  test "runPostAnalysis skips when no prediction section":
    let content = "# Ticket\n\nNo prediction here.\n"
    let updated = runPostAnalysis(content, "0051", "done", 1, 100)
    check "## Post-Analysis" notin updated
    check updated == content

  test "runTicketPrediction appends prediction to ticket markdown":
    withTempRepo("scriptorium_test_prediction_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      addTicketToPlan(repoPath, "in-progress", "0099-pred.md",
        "# Predict Me\n\n**Area:** test-area\n\n**Worktree:** /tmp/fake\n")

      proc predictionRunner(request: AgentRunRequest): AgentRunResult =
        ## Return a fake prediction response.
        result = AgentRunResult(
          backend: harnessCodex,
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          lastMessage: """{"predicted_difficulty": "easy", "predicted_duration_minutes": 15, "reasoning": "Small isolated change."}""",
          timeoutKind: "none",
        )

      runTicketPrediction(repoPath, "tickets/in-progress/0099-pred.md", predictionRunner)

      let (ticketContent, rc) = execCmdEx(
        "git -C " & quoteShell(repoPath) & " show scriptorium/plan:tickets/in-progress/0099-pred.md"
      )
      check rc == 0
      check "## Prediction" in ticketContent
      check "- predicted_difficulty: easy" in ticketContent
      check "- predicted_duration_minutes: 15" in ticketContent
    )

  test "runTicketPrediction logs warning and continues on failure":
    withTempRepo("scriptorium_test_prediction_fail_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      addTicketToPlan(repoPath, "in-progress", "0098-predfail.md",
        "# Predict Fail\n\n**Area:** test-area\n\n**Worktree:** /tmp/fake\n")

      proc failRunner(request: AgentRunRequest): AgentRunResult =
        ## Return a failing result to test best-effort behavior.
        result = AgentRunResult(
          backend: harnessCodex,
          exitCode: 1,
          attempt: 1,
          attemptCount: 1,
          lastMessage: "",
          timeoutKind: "none",
        )

      # Should not raise - prediction is best-effort.
      runTicketPrediction(repoPath, "tickets/in-progress/0098-predfail.md", failRunner)

      let (ticketContent, rc) = execCmdEx(
        "git -C " & quoteShell(repoPath) & " show scriptorium/plan:tickets/in-progress/0098-predfail.md"
      )
      check rc == 0
      check "## Prediction" notin ticketContent
    )

suite "health cache persistence":
  test "readHealthCache returns empty table when file does not exist":
    let tmp = getTempDir() / "scriptorium_test_health_cache_empty"
    createDir(tmp)
    defer: removeDir(tmp)

    let cache = readHealthCache(tmp)
    check cache.len == 0

  test "writeHealthCache creates directory and file then readHealthCache round-trips":
    let tmp = getTempDir() / "scriptorium_test_health_cache_roundtrip"
    createDir(tmp)
    defer: removeDir(tmp)

    var cache = initTable[string, HealthCacheEntry]()
    cache["abc123"] = HealthCacheEntry(
      healthy: true,
      timestamp: "2026-03-13T12:00:00Z",
      test_exit_code: 0,
      integration_test_exit_code: 0,
      test_wall_seconds: 45,
      integration_test_wall_seconds: 120,
    )
    cache["def456"] = HealthCacheEntry(
      healthy: false,
      timestamp: "2026-03-13T13:00:00Z",
      test_exit_code: 1,
      integration_test_exit_code: 0,
      test_wall_seconds: 10,
      integration_test_wall_seconds: 0,
    )

    writeHealthCache(tmp, cache)

    check fileExists(tmp / "health" / "cache.json")

    let loaded = readHealthCache(tmp)
    check loaded.len == 2
    check loaded["abc123"].healthy == true
    check loaded["abc123"].test_exit_code == 0
    check loaded["abc123"].integration_test_exit_code == 0
    check loaded["abc123"].test_wall_seconds == 45
    check loaded["abc123"].integration_test_wall_seconds == 120
    check loaded["def456"].healthy == false
    check loaded["def456"].test_exit_code == 1

  test "readHealthCache parses JSON with correct field types":
    let tmp = getTempDir() / "scriptorium_test_health_cache_parse"
    createDir(tmp / "health")
    defer: removeDir(tmp)

    let jsonContent = """{"commit1": {"healthy": true, "timestamp": "2026-03-13T12:00:00Z", "test_exit_code": 0, "integration_test_exit_code": 0, "test_wall_seconds": 30, "integration_test_wall_seconds": 60}}"""
    writeFile(tmp / "health" / "cache.json", jsonContent)

    let cache = readHealthCache(tmp)
    check cache.len == 1
    check "commit1" in cache
    check cache["commit1"].healthy == true
    check cache["commit1"].timestamp == "2026-03-13T12:00:00Z"
    check cache["commit1"].test_wall_seconds == 30
    check cache["commit1"].integration_test_wall_seconds == 60

  test "writeHealthCache overwrites existing cache":
    let tmp = getTempDir() / "scriptorium_test_health_cache_overwrite"
    createDir(tmp)
    defer: removeDir(tmp)

    var cache1 = initTable[string, HealthCacheEntry]()
    cache1["abc"] = HealthCacheEntry(healthy: true, timestamp: "t1", test_exit_code: 0, integration_test_exit_code: 0, test_wall_seconds: 1, integration_test_wall_seconds: 2)
    writeHealthCache(tmp, cache1)

    var cache2 = initTable[string, HealthCacheEntry]()
    cache2["abc"] = HealthCacheEntry(healthy: true, timestamp: "t1", test_exit_code: 0, integration_test_exit_code: 0, test_wall_seconds: 1, integration_test_wall_seconds: 2)
    cache2["def"] = HealthCacheEntry(healthy: false, timestamp: "t2", test_exit_code: 1, integration_test_exit_code: 0, test_wall_seconds: 5, integration_test_wall_seconds: 0)
    writeHealthCache(tmp, cache2)

    let loaded = readHealthCache(tmp)
    check loaded.len == 2
    check "abc" in loaded
    check "def" in loaded

suite "per-ticket submit_pr state":
  test "consumeSubmitPrSummary with ticketId returns per-ticket summary":
    discard consumeSubmitPrSummary()
    setActiveTicketWorktree("/tmp/wt-a", "0001")
    setActiveTicketWorktree("/tmp/wt-b", "0002")
    defer:
      clearActiveTicketWorktree("0001")
      clearActiveTicketWorktree("0002")

    recordSubmitPrSummary("summary for 0001", "0001")
    recordSubmitPrSummary("summary for 0002", "0002")

    check consumeSubmitPrSummary("0001") == "summary for 0001"
    check consumeSubmitPrSummary("0002") == "summary for 0002"
    check consumeSubmitPrSummary("0001") == ""
    check consumeSubmitPrSummary("0002") == ""

  test "consumeSubmitPrSummary without ticketId returns first available":
    discard consumeSubmitPrSummary()
    recordSubmitPrSummary("some summary", "0005")
    let result = consumeSubmitPrSummary()
    check result == "some summary"
    check consumeSubmitPrSummary() == ""

  test "setActiveTicketWorktree registers multiple entries":
    clearActiveTicketWorktree()
    setActiveTicketWorktree("/tmp/wt-a", "0010")
    setActiveTicketWorktree("/tmp/wt-b", "0011")
    defer: clearActiveTicketWorktree()

    let a = getActiveTicketWorktree("0010")
    check a.worktreePath == "/tmp/wt-a"
    check a.ticketId == "0010"

    let b = getActiveTicketWorktree("0011")
    check b.worktreePath == "/tmp/wt-b"
    check b.ticketId == "0011"

  test "clearActiveTicketWorktree with ticketId removes only that entry":
    clearActiveTicketWorktree()
    setActiveTicketWorktree("/tmp/wt-a", "0020")
    setActiveTicketWorktree("/tmp/wt-b", "0021")
    defer: clearActiveTicketWorktree()

    clearActiveTicketWorktree("0020")
    let a = getActiveTicketWorktree("0020")
    check a.worktreePath == ""
    let b = getActiveTicketWorktree("0021")
    check b.worktreePath == "/tmp/wt-b"

  test "clearActiveTicketWorktree without ticketId removes all entries":
    setActiveTicketWorktree("/tmp/wt-a", "0030")
    setActiveTicketWorktree("/tmp/wt-b", "0031")
    clearActiveTicketWorktree()
    check getActiveTicketWorktree("0030").worktreePath == ""
    check getActiveTicketWorktree("0031").worktreePath == ""

suite "agent slot types":
  test "AgentSlot stores ticket metadata with role":
    let slot = AgentSlot(
      role: arCoder,
      ticketId: "0042",
      branch: "scriptorium/ticket-0042",
      worktree: "/tmp/worktrees/0042",
      startTime: 1234567890.0,
    )
    check slot.role == arCoder
    check slot.ticketId == "0042"
    check slot.branch == "scriptorium/ticket-0042"
    check slot.worktree == "/tmp/worktrees/0042"
    check slot.startTime == 1234567890.0

  test "AgentSlot manager uses areaId with empty branch and worktree":
    let slot = AgentSlot(
      role: arManager,
      areaId: "backend-api",
      startTime: 1234567890.0,
    )
    check slot.role == arManager
    check slot.areaId == "backend-api"
    check slot.branch == ""
    check slot.worktree == ""

  test "runningAgentCount returns zero initially":
    check runningAgentCount() == 0

  test "emptySlotCount returns maxAgents when no agents running":
    check emptySlotCount(4) == 4

suite "token budget tracking":
  setup:
    ticketStdoutBytes.clear()

  test "getSessionStdoutBytes sums all ticket values":
    ticketStdoutBytes["0001"] = 1000
    ticketStdoutBytes["0002"] = 2000
    ticketStdoutBytes["0003"] = 3000
    check getSessionStdoutBytes() == 6000

  test "getSessionStdoutBytes returns 0 when empty":
    check getSessionStdoutBytes() == 0

  test "isTokenBudgetExceeded returns false when tokenBudgetMB is 0":
    ticketStdoutBytes["0001"] = 100 * 1024 * 1024
    check isTokenBudgetExceeded(0) == false

  test "isTokenBudgetExceeded returns false when tokenBudgetMB is negative":
    ticketStdoutBytes["0001"] = 100 * 1024 * 1024
    check isTokenBudgetExceeded(-1) == false

  test "isTokenBudgetExceeded returns true when budget exceeded":
    ticketStdoutBytes["0001"] = 5 * 1024 * 1024
    ticketStdoutBytes["0002"] = 6 * 1024 * 1024
    check isTokenBudgetExceeded(10) == true

  test "isTokenBudgetExceeded returns false when under budget":
    ticketStdoutBytes["0001"] = 2 * 1024 * 1024
    ticketStdoutBytes["0002"] = 3 * 1024 * 1024
    check isTokenBudgetExceeded(10) == false

  test "running agents not interrupted when budget exceeded":
    ## Verify that ticketStdoutBytes entries remain intact when budget is exceeded.
    ticketStdoutBytes["0001"] = 5 * 1024 * 1024
    ticketStdoutBytes["0002"] = 6 * 1024 * 1024
    let exceeded = isTokenBudgetExceeded(10)
    check exceeded == true
    # Existing entries are not cleared or modified.
    check ticketStdoutBytes["0001"] == 5 * 1024 * 1024
    check ticketStdoutBytes["0002"] == 6 * 1024 * 1024

suite "rate limit detection and backpressure":
  setup:
    resetRateLimitState()

  test "isRateLimited detects HTTP 429 rate limit":
    check isRateLimited("Error: HTTP 429 Too Many Requests") == true
    check isRateLimited("rate limit exceeded") == true
    check isRateLimited("rate_limit_error: quota exceeded") == true
    check isRateLimited("ratelimit hit, please retry") == true
    check isRateLimited("Error 429: rate limited") == true

  test "isRateLimited returns false for normal output":
    check isRateLimited("") == false
    check isRateLimited("Successfully completed task") == false
    check isRateLimited("Exit code 0") == false
    check isRateLimited("429 lines of code written") == false

  test "backoff timing increases exponentially":
    resetRateLimitState()
    recordRateLimit("0001")
    let backoff1 = rateLimitBackoffSeconds()
    check backoff1 == 2.0

    recordRateLimit("0002")
    let backoff2 = rateLimitBackoffSeconds()
    check backoff2 == 4.0

    recordRateLimit("0003")
    let backoff3 = rateLimitBackoffSeconds()
    check backoff3 == 8.0

    recordRateLimit("0004")
    let backoff4 = rateLimitBackoffSeconds()
    check backoff4 == 16.0

  test "backoff is capped at maximum":
    resetRateLimitState()
    for i in 1..20:
      recordRateLimit("0001")
    let backoff = rateLimitBackoffSeconds()
    check backoff == 120.0

  test "effective concurrency reduced on rate limit":
    resetRateLimitState()
    check effectiveMaxAgents(4) == 4

    recordRateLimit("0001")
    check effectiveMaxAgents(4) == 3

    recordRateLimit("0002")
    check effectiveMaxAgents(4) == 2

  test "effective concurrency never drops below 1":
    resetRateLimitState()
    for i in 1..10:
      recordRateLimit("0001")
    check effectiveMaxAgents(4) == 1

  test "concurrency restored after backoff expires":
    resetRateLimitState()
    recordRateLimit("0001")
    check effectiveMaxAgents(4) == 3
    check isRateLimitBackoffActive() == true

    # Simulate backoff expiry by setting backoff time in the past.
    rateLimitBackoffUntil = epochTime() - 1.0
    check isRateLimitBackoffActive() == false
    check effectiveMaxAgents(4) == 4
    check rateLimitConsecutiveCount == 0
    check rateLimitConcurrencyReduction == 0

  test "resetRateLimitState clears all state":
    recordRateLimit("0001")
    recordRateLimit("0002")
    check rateLimitConsecutiveCount == 2
    check rateLimitConcurrencyReduction > 0
    check rateLimitBackoffUntil > 0.0

    resetRateLimitState()
    check rateLimitConsecutiveCount == 0
    check rateLimitConcurrencyReduction == 0
    check rateLimitBackoffUntil == 0.0

  test "running agents not interrupted by backpressure":
    resetRateLimitState()
    recordRateLimit("0001")
    check isRateLimitBackoffActive() == true
    # Backpressure only affects new agent starts via effectiveMaxAgents.
    # Running agents tracked in runningAgentSlots are never modified.
    check runningAgentCount() == 0
