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
