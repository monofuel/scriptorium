<!-- ticket: 0077-log-review-reasoning.md -->
# Log review reasoning from review agent sessions

**Area:** review-agent
**Difficulty:** easy

## Problem

The spec (Section 9, Review Lifecycle Logging) requires: "Review reasoning (not just the decision) must be logged so violations are traceable in the review logs." Currently, `runReviewAgent` in `src/scriptorium/merge_queue.nim` only logs the decision (approve/request_changes) and a truncated feedback summary. The review agent's reasoning output (its text messages explaining why it made its decision) is not captured or logged.

## Requirements

1. **Capture review agent reasoning** (`src/scriptorium/merge_queue.nim:183-268`, `runReviewAgent`):
   - The `AgentRunRequest.onEvent` callback currently only logs tool events at DEBUG level. Add capture of `agentEventMessage` events to accumulate the review agent's reasoning text.
   - Store accumulated reasoning in a local variable (e.g., `var reviewReasoning = ""`). Append each message event's text.
   - After the agent completes, log the reasoning at DEBUG level: `review[<ticketId>]: reasoning: <text>` (truncate to a reasonable limit, e.g., 2000 chars).

2. **Include reasoning in review notes** (`src/scriptorium/merge_queue.nim`):
   - When appending the review note to the ticket markdown, include a `**Review Reasoning:**` field with the captured reasoning text (truncated to 2000 chars if needed).
   - This applies to all three outcomes: approve, approve_with_warnings, and request_changes.

3. **Tests**:
   - Add a unit test for `runReviewAgent` that uses a fake runner, verifies the `onEvent` callback captures message events, and checks that reasoning appears in the ticket's review note.

## Key files
- `src/scriptorium/merge_queue.nim:183-268` — `runReviewAgent` proc
- `src/scriptorium/agent_runner.nim` — `AgentStreamEvent` type definition
- `tests/test_scriptorium.nim` — existing review agent tests

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0083-log-review-reasoning-from-review-agent-sessions

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Single-file change in merge_queue.nim to accumulate message events and append reasoning to review notes, plus a straightforward unit test — one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 3\n- Attempt Count: 3\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0083-log-review-reasoning-from-review-agent-sessions/.scriptorium/logs/0083/attempt-03.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0083-log-review-reasoning-from-review-agent-sessions/.scriptorium/logs/0083/attempt-03.last_message.txt\n
### Agent Last Message
```text
Work is complete. The PR has been submitted for ticket 0083.

**Summary of changes:**

- **`src/scriptorium/merge_queue.nim`**: Added `ReviewReasoningMaxChars` constant (2000), accumulate `agentEventMessage` events in `reviewReasoning` variable during `runReviewAgent`, log reasoning at DEBUG level, and append `**Review Reasoning:**` to the ticket review note for all outcomes.
- **`tests/test_scriptorium.nim`**: Two new tests — one verifying reasoning capture and inclusion in review notes, another verifying truncation of long reasoning text.
```

### Agent Stdout Tail
```text
ewReasoningMaxChars` constant (2000), accumulate `agentEventMessage` events in `reviewReasoning` variable during `runReviewAgent`, log reasoning at DEBUG level, and append `**Review Reasoning:**` to the ticket review note for all outcomes.\n- **`tests/test_scriptorium.nim`**: Two new tests — one verifying reasoning capture and inclusion in review notes, another verifying truncation of long reasoning text.","stop_reason":"end_turn","session_id":"e18ab8cd-2914-4ecd-91b7-e89684efca38","total_cost_usd":0.690163,"usage":{"input_tokens":3490,"cache_creation_input_tokens":33512,"cache_read_input_tokens":647576,"output_tokens":5579,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":33512},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":3490,"outputTokens":5579,"cacheReadInputTokens":647576,"cacheCreationInputTokens":33512,"webSearchRequests":0,"costUSD":0.690163,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"597f5067-c5c0-4098-908e-550972a08faa"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 38s

## Merge Queue Failure
- Summary: Capture review agent reasoning from agentEventMessage events and include it in ticket review notes. Added ReviewReasoningMaxChars constant (2000), accumulate message events in onEvent callback, log reasoning at DEBUG level, and append **Review Reasoning:** field to ticket markdown for all review outcomes. Includes two unit tests for reasoning capture and truncation.\n
### Merge Output
```text
Auto-merging src/scriptorium/merge_queue.nim
CONFLICT (content): Merge conflict in src/scriptorium/merge_queue.nim
Automatic merge failed; fix conflicts and then commit the result.
```

## Metrics
- wall_time_seconds: 2114
- coding_wall_seconds: 2069
- test_wall_seconds: 0
- attempt_count: 3
- outcome: reopened
- failure_reason: merge_conflict
- model: claude-opus-4-6
- stdout_bytes: 518087

## Post-Analysis
- actual_difficulty: complex
- prediction_accuracy: underestimated
- brief_summary: Predicted easy, actual was complex with 3 attempt(s) in 35m14s.
