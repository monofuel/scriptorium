import
  std/[strformat, strutils, tables, times],
  ./[agent_runner, prompt_builders, shared_state]

const
  AgentMessagePreviewChars* = 1200
  AgentStdoutPreviewChars* = 1200
  MergeQueueOutputPreviewChars* = 2000

proc formatDuration*(seconds: float): string =
  ## Format a duration in seconds as a human-readable string like 1h23m or 3m12s.
  let totalSecs = seconds.int
  if totalSecs < 60:
    result = $totalSecs & "s"
  elif totalSecs < 3600:
    let mins = totalSecs div 60
    let secs = totalSecs mod 60
    result = $mins & "m" & $secs & "s"
  else:
    let hours = totalSecs div 3600
    let mins = (totalSecs mod 3600) div 60
    result = $hours & "h" & $mins & "m"

proc formatAgentRunNote*(model: string, runResult: AgentRunResult): string =
  ## Format a markdown note summarizing one coding-agent run.
  let messagePreview = truncateTail(runResult.lastMessage.strip(), AgentMessagePreviewChars)
  let stdoutPreview = truncateTail(runResult.stdout.strip(), AgentStdoutPreviewChars)
  result =
    "## Agent Run\n" &
    fmt"- Model: {model}\n" &
    fmt"- Backend: {runResult.backend}\n" &
    fmt"- Exit Code: {runResult.exitCode}\n" &
    fmt"- Attempt: {runResult.attempt}\n" &
    fmt"- Attempt Count: {runResult.attemptCount}\n" &
    fmt"- Timeout: {runResult.timeoutKind}\n" &
    fmt"- Log File: {runResult.logFile}\n" &
    fmt"- Last Message File: {runResult.lastMessageFile}\n"

  if messagePreview.len > 0:
    result &=
      "\n### Agent Last Message\n" &
      "```text\n" &
      messagePreview & "\n" &
      "```\n"

  if stdoutPreview.len > 0:
    result &=
      "\n### Agent Stdout Tail\n" &
      "```text\n" &
      stdoutPreview & "\n" &
      "```\n"

proc appendAgentRunNote*(ticketContent: string, model: string, runResult: AgentRunResult): string =
  ## Append a formatted coding-agent run note to a ticket markdown document.
  let base = ticketContent.strip()
  let note = formatAgentRunNote(model, runResult).strip()
  result = base & "\n\n" & note & "\n"

proc formatMetricsNote*(ticketId: string, outcome: string, failureReason: string): string =
  ## Format a structured metrics section for a completed ticket.
  let wallTimeSeconds = block:
    let startTime = ticketStartTimes.getOrDefault(ticketId, 0.0)
    if startTime > 0.0: int(epochTime() - startTime) else: 0
  let codingWallSeconds = int(ticketCodingWalls.getOrDefault(ticketId, 0.0))
  let testWallSeconds = int(ticketTestWalls.getOrDefault(ticketId, 0.0))
  let attemptCount = ticketAttemptCounts.getOrDefault(ticketId, 0)
  let model = ticketModels.getOrDefault(ticketId, "unknown")
  let stdoutBytes = ticketStdoutBytes.getOrDefault(ticketId, 0)
  result =
    "## Metrics\n" &
    &"- wall_time_seconds: {wallTimeSeconds}\n" &
    &"- coding_wall_seconds: {codingWallSeconds}\n" &
    &"- test_wall_seconds: {testWallSeconds}\n" &
    &"- attempt_count: {attemptCount}\n" &
    &"- outcome: {outcome}\n" &
    &"- failure_reason: {failureReason}\n" &
    &"- model: {model}\n" &
    &"- stdout_bytes: {stdoutBytes}\n"

proc appendMetricsNote*(ticketContent: string, ticketId: string, outcome: string, failureReason: string): string =
  ## Append a structured metrics section to a ticket markdown document.
  let base = ticketContent.strip()
  let note = formatMetricsNote(ticketId, outcome, failureReason).strip()
  result = base & "\n\n" & note & "\n"

proc formatPredictionNote*(prediction: TicketPrediction): string =
  ## Format a prediction section for appending to ticket markdown.
  result =
    "## Prediction\n" &
    &"- predicted_difficulty: {prediction.difficulty}\n" &
    &"- predicted_duration_minutes: {prediction.durationMinutes}\n" &
    &"- reasoning: {prediction.reasoning}\n"

proc appendPredictionNote*(ticketContent: string, prediction: TicketPrediction): string =
  ## Append a prediction section to a ticket markdown document.
  let base = ticketContent.strip()
  let note = formatPredictionNote(prediction).strip()
  result = base & "\n\n" & note & "\n"

proc formatPostAnalysisNote*(actualDifficulty: string, predictionAccuracy: string, briefSummary: string): string =
  ## Format a post-analysis section for appending to ticket markdown.
  result =
    "## Post-Analysis\n" &
    &"- actual_difficulty: {actualDifficulty}\n" &
    &"- prediction_accuracy: {predictionAccuracy}\n" &
    &"- brief_summary: {briefSummary}\n"

proc appendPostAnalysisNote*(ticketContent: string, actualDifficulty: string, predictionAccuracy: string, briefSummary: string): string =
  ## Append a post-analysis section to a ticket markdown document.
  let base = ticketContent.strip()
  let note = formatPostAnalysisNote(actualDifficulty, predictionAccuracy, briefSummary).strip()
  result = base & "\n\n" & note & "\n"

proc formatMergeFailureNote*(summary: string, mergeOutput: string, checkOutput: string, failedStep: string): string =
  ## Format a ticket note for failed merge queue processing.
  let mergePreview = truncateTail(mergeOutput.strip(), MergeQueueOutputPreviewChars)
  let checkPreview = truncateTail(checkOutput.strip(), MergeQueueOutputPreviewChars)
  result =
    "## Merge Queue Failure\n" &
    fmt"- Summary: {summary}\n"
  if failedStep.len > 0:
    result &= fmt"- Failed gate: {failedStep}\n"
  if mergePreview.len > 0:
    result &=
      "\n### Merge Output\n" &
      "```text\n" &
      mergePreview & "\n" &
      "```\n"
  if checkPreview.len > 0:
    result &=
      "\n### Quality Check Output\n" &
      "```text\n" &
      checkPreview & "\n" &
      "```\n"

proc formatMergeSuccessNote*(summary: string, checkOutput: string): string =
  ## Format a ticket note for successful merge queue processing.
  let checkPreview = truncateTail(checkOutput.strip(), MergeQueueOutputPreviewChars)
  result =
    "## Merge Queue Success\n" &
    fmt"- Summary: {summary}\n"
  if checkPreview.len > 0:
    result &=
      "\n### Quality Check Output\n" &
      "```text\n" &
      checkPreview & "\n" &
      "```\n"
