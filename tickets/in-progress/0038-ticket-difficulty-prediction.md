# Ticket Difficulty Prediction Before Assignment

**Area:** ticket-prediction

## Description

Before a ticket is assigned to a coding agent, run a lightweight prediction prompt to estimate ticket difficulty and expected duration. Append the prediction to the ticket markdown and log it.

## Current State

No prediction infrastructure exists. Tickets are assigned directly to coding agents without any pre-analysis. The codex harness is available for running agent calls, and `TicketDocument` holds ticket content.

## Requirements

- Before ticket assignment, invoke a prediction prompt via the configured coding agent model (codex harness).
- Prediction prompt context includes: ticket content, relevant area content, current spec summary.
- Prediction output fields:
  - `predicted_difficulty`: `trivial`, `easy`, `medium`, `hard`, or `complex`.
  - `predicted_duration_minutes`: estimated wall time in minutes.
  - `reasoning`: brief explanation of the prediction.
- Log at INFO level: `ticket <id>: predicted difficulty=<level> duration=<n>min`.
- Append prediction as a `## Prediction` section in the ticket markdown before coding begins.
- Prediction must not significantly delay ticket assignment (use a short timeout or fast model invocation).

## Implementation Notes

- Create a prediction prompt template that asks the model to assess difficulty given the ticket and area content.
- Parse structured output (JSON or key-value) from the model response.
- Call the codex harness with a short timeout for the prediction.
- If prediction fails or times out, log a warning and proceed with assignment (prediction is best-effort).
- Append the prediction section to ticket markdown and commit to plan branch before starting the coding agent.

## Spec References

- Section 18: Ticket Difficulty Prediction (V3).

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0038-ticket-difficulty-prediction

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0038-ticket-difficulty-prediction/.scriptorium/logs/0038/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0038-ticket-difficulty-prediction/.scriptorium/logs/0038/attempt-01.last_message.txt\n
### Agent Last Message
```text
The PR has been submitted successfully. 

Here's a summary of the changes:

**New files:**
- `src/scriptorium/prompts/ticket_prediction.md` - Prompt template that asks the model to assess ticket difficulty given ticket content, area context, and spec summary

**Modified files:**
- `src/scriptorium/prompt_catalog.nim` - Added `TicketPredictionTemplate` constant
- `src/scriptorium/orchestrator.nim` - Added:
  - `TicketPrediction` type with difficulty, durationMinutes, reasoning fields
  - `parsePredictionResponse` - Parses JSON from model response, validates difficulty levels
  - `formatPredictionNote`/`appendPredictionNote` - Formats `## Prediction` markdown section
  - `buildPredictionPrompt` - Renders prediction prompt template with ticket, area, and spec context
  - `predictTicketDifficulty` - Runs the prediction agent call with short timeouts (30s no-output, 60s hard)
  - `runTicketPrediction` - Best-effort wrapper that catches errors and logs warnings
  - Wired into `executeOldestOpenTicket` between assignment and coding agent execution
- `tests/test_scriptorium.nim` - 9 new tests in "ticket difficulty prediction" suite covering parsing, formatting, and integration
```

### Agent Stdout Tail
```text
destOpenTicket` between assignment and coding agent execution\n- `tests/test_scriptorium.nim` - 9 new tests in \"ticket difficulty prediction\" suite covering parsing, formatting, and integration","stop_reason":"end_turn","session_id":"225706e6-9169-4e8a-a496-42df3312601f","total_cost_usd":4.1256543,"usage":{"input_tokens":94,"cache_creation_input_tokens":75656,"cache_read_input_tokens":5757381,"output_tokens":20710,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":75656,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":94,"outputTokens":20710,"cacheReadInputTokens":5757381,"cacheCreationInputTokens":75656,"webSearchRequests":0,"costUSD":3.8697604999999986,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":64,"outputTokens":7000,"cacheReadInputTokens":1040623,"cacheCreationInputTokens":93414,"webSearchRequests":0,"costUSD":0.2558938,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"80a79e7e-933c-4342-94c5-ffb2f8d5da7a"}
```
