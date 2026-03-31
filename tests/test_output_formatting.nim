## Unit tests for output formatting functions.

import
  std/[strutils, tables, times, unittest],
  scriptorium/[agent_runner, config, output_formatting, prompt_builders, shared_state,
    ticket_metadata]

proc makeResult(
  lastMessage = "",
  stdout = "",
  exitCode = 0,
  attempt = 1,
  attemptCount = 1,
): AgentRunResult =
  ## Build an AgentRunResult with sensible defaults for testing.
  result = AgentRunResult(
    backend: harnessClaudeCode,
    exitCode: exitCode,
    attempt: attempt,
    attemptCount: attemptCount,
    stdout: stdout,
    logFile: "/tmp/log.txt",
    lastMessageFile: "/tmp/last_msg.txt",
    lastMessage: lastMessage,
    timeoutKind: "none",
  )

suite "formatAgentRunNote":
  test "includes all required fields":
    let note = formatAgentRunNote("opus-4", makeResult())
    check note.contains("Model: opus-4")
    check note.contains("Backend: claude-code")
    check note.contains("Exit Code: 0")
    check note.contains("Attempt: 1")
    check note.contains("Attempt Count: 1")
    check note.contains("Timeout: none")
    check note.contains("Log File: /tmp/log.txt")
    check note.contains("Last Message File: /tmp/last_msg.txt")

  test "includes last message section when non-empty":
    let note = formatAgentRunNote("opus-4", makeResult(lastMessage = "hello world"))
    check note.contains("### Agent Last Message")
    check note.contains("hello world")

  test "includes stdout tail section when non-empty":
    let note = formatAgentRunNote("opus-4", makeResult(stdout = "build ok"))
    check note.contains("### Agent Stdout Tail")
    check note.contains("build ok")

  test "omits last message section when empty":
    let note = formatAgentRunNote("opus-4", makeResult(lastMessage = ""))
    check not note.contains("### Agent Last Message")

  test "omits stdout tail section when empty":
    let note = formatAgentRunNote("opus-4", makeResult(stdout = ""))
    check not note.contains("### Agent Stdout Tail")

  test "truncates long lastMessage to AgentMessagePreviewChars":
    let long = 'x'.repeat(AgentMessagePreviewChars + 500)
    let note = formatAgentRunNote("m", makeResult(lastMessage = long))
    # The preview inside the note should be at most AgentMessagePreviewChars.
    let expected = truncateTail(long.strip(), AgentMessagePreviewChars)
    check note.contains(expected)
    check not note.contains(long)

  test "truncates long stdout to AgentStdoutPreviewChars":
    let long = 'y'.repeat(AgentStdoutPreviewChars + 500)
    let note = formatAgentRunNote("m", makeResult(stdout = long))
    let expected = truncateTail(long.strip(), AgentStdoutPreviewChars)
    check note.contains(expected)
    check not note.contains(long)

suite "appendAgentRunNote":
  test "appends run note to existing ticket content":
    let ticket = "# My Ticket\n\nSome content."
    let res = appendAgentRunNote(ticket, "opus-4", makeResult())
    check res.startsWith("# My Ticket")
    check res.contains("## Agent Run")
    # Base and note separated by blank line.
    check res.contains("Some content.\n\n## Agent Run")

  test "strips trailing whitespace from base content":
    let ticket = "# Ticket   \n\n  "
    let res = appendAgentRunNote(ticket, "m", makeResult())
    # After strip, base is "# Ticket" — no trailing spaces before separator.
    check res.startsWith("# Ticket\n\n## Agent Run")

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
