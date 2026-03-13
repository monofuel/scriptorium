# Ticket Post-Analysis After Completion

**Area:** ticket-prediction

## Description

After a ticket reaches done, reopened, or parked state, run a brief post-analysis comparing predicted vs actual metrics. Append the analysis to the ticket markdown and log it.

## Current State

No post-analysis infrastructure exists. Tickets move to terminal states without any retrospective analysis. Per-ticket metrics (from ticket 0037) and prediction data (from ticket 0038) will provide the inputs for comparison.

## Requirements

- After a ticket reaches done or is reopened/parked, run a post-analysis.
- Compare predicted vs actual metrics:
  - Predicted difficulty vs actual attempt count and outcome.
  - Predicted duration vs actual wall time.
- Post-analysis output fields:
  - `actual_difficulty`: assessment based on actual metrics (`trivial`, `easy`, `medium`, `hard`, `complex`).
  - `prediction_accuracy`: `accurate`, `underestimated`, or `overestimated`.
  - `brief_summary`: one-sentence summary of what happened.
- Log at INFO level: `ticket <id>: post-analysis: predicted=<level> actual=<level> accuracy=<accuracy> wall=<duration>`.
- Append as a `## Post-Analysis` section in the ticket markdown.

## Implementation Notes

- Read the prediction section from the ticket markdown to get predicted values.
- Read actual metrics from the metrics section (ticket 0037) or from orchestrator state.
- Classify actual difficulty based on attempt count, outcome, and wall time:
  - e.g., 1 attempt + done + short wall = trivial/easy; multiple attempts + reopened = hard/complex.
- Determine prediction accuracy by comparing predicted vs actual difficulty and duration.
- Generate brief_summary describing what happened (can be a simple template, no LLM call needed).
- If no prediction section exists (prediction was skipped), log and skip post-analysis.
- Append the post-analysis section and commit to plan branch.

## Spec References

- Section 19: Ticket Post-Analysis (V3).

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0039-ticket-post-analysis

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0039-ticket-post-analysis/.scriptorium/logs/0039/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0039-ticket-post-analysis/.scriptorium/logs/0039/attempt-01.last_message.txt\n
### Agent Last Message
```text
Work is complete. Here's a summary of what was implemented:

**Changes in `src/scriptorium/orchestrator.nim`:**
- Added `PostAnalysisCommitPrefix` constant
- `parsePredictionFromContent` - extracts predicted difficulty/duration from ticket markdown's `## Prediction` section
- `classifyActualDifficulty` - classifies actual difficulty based on attempt count, outcome, and wall time (trivial/easy/medium/hard/complex)
- `compareDifficulty` - compares predicted vs actual to determine accuracy (accurate/underestimated/overestimated)
- `formatPostAnalysisNote` / `appendPostAnalysisNote` - formats and appends `## Post-Analysis` section
- `runPostAnalysis` - orchestrates the full analysis; skips if no prediction section exists
- Integrated `runPostAnalysis` at all 5 terminal state transitions: done (merge success), parked (stuck), reopened (merge failure), reopened (worktree missing), reopened (stall/no submit_pr)

**Changes in `tests/test_scriptorium.nim`:**
- 18 new tests covering all post-analysis functions: parsing predictions from markdown, classifying actual difficulty, comparing difficulties, formatting output, and the full runPostAnalysis flow (including skip behavior)
```

### Agent Stdout Tail
```text
lysis functions: parsing predictions from markdown, classifying actual difficulty, comparing difficulties, formatting output, and the full runPostAnalysis flow (including skip behavior)","stop_reason":"end_turn","session_id":"a4ba4476-105d-4b92-9757-fb600193c574","total_cost_usd":4.907472900000002,"usage":{"input_tokens":115,"cache_creation_input_tokens":84263,"cache_read_input_tokens":7085111,"output_tokens":26144,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":84263,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":115,"outputTokens":26144,"cacheReadInputTokens":7085111,"cacheCreationInputTokens":84263,"webSearchRequests":0,"costUSD":4.7233742500000035,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":40,"outputTokens":5706,"cacheReadInputTokens":821849,"cacheCreationInputTokens":58675,"webSearchRequests":0,"costUSD":0.18409865,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"943df347-2b9f-4551-9163-0ba9fa14f929"}
```
