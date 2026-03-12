# Timing Capture Infrastructure For Per-Ticket Metrics

**Area:** ticket-metrics

## Description

Add timing capture at key points in the ticket lifecycle so that per-ticket metrics (wall time, coding wall time, test wall time) can be computed and persisted.

## Current State

- The harness modules have `elapsedMs()` helpers for timeout checking, but timing is not captured for metrics purposes.
- The orchestrator tick loop logs per-component durations at DEBUG level but does not store them.
- `runWorktreeMakeTest()` returns exit code and output but no duration.
- No ticket-level timing state is maintained across the lifecycle.

## Requirements

- Track and store the following timing data per ticket:
  - **Assignment start time**: recorded when a ticket transitions from open to in-progress.
  - **Coding agent wall time**: elapsed time for each coding agent invocation (per attempt and cumulative).
  - **Test wall time**: elapsed time for each `make test` invocation (merge queue tests and stall-check tests), cumulative.
  - **Total wall time**: from assignment to final done/reopen/park.

- Timing values stored in seconds (float or int) for machine readability.
- Timing state must survive across the tick loop (stored in orchestrator state or a per-ticket tracking table).

## Implementation Notes

- Add a `TicketTimings` object or similar to track per-ticket start times and accumulated durations.
- Record `epochTime()` at assignment, before/after coding agent runs, and before/after `make test` calls.
- Update `runWorktreeMakeTest()` or its callers to capture test duration.
- Store timing data in orchestrator state keyed by ticket ID.
- This ticket provides the infrastructure; the next ticket (metrics persistence) will format and write these to markdown.

## Spec References

- Section 15: Per-Ticket Metrics In Agent Run Notes (V3).

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0036-timing-capture-infrastructure

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0036-timing-capture-infrastructure/.scriptorium/logs/0036/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0036-timing-capture-infrastructure/.scriptorium/logs/0036/attempt-01.last_message.txt\n
### Agent Last Message
```text
ges are committed. Here's a summary of what was done:

**Changes in `src/scriptorium/orchestrator.nim`:**
- **Accumulate stall-check test wall time**: After `runWorktreeMakeTest()` during stall detection, the test duration is now accumulated into `ticketTestWalls[ticketId]`
- **Accumulate merge queue test wall time**: On successful merge, the merge queue quality check duration is added to any prior stall-check test time before recording to `sessionStats.completedTestWalls`
- **Initialize timing at assignment**: `ticketCodingWalls` and `ticketTestWalls` are initialized to `0.0` when a ticket is assigned (alongside the existing `ticketStartTimes` and `ticketAttemptCounts`)
- **Clean up timing state on all terminal paths**: All four timing tables are cleaned up on agent reopen, merge queue reopen, merge queue park, and worktree-missing reopen
- **Export timing tables**: Made `ticketStartTimes`, `ticketAttemptCounts`, `ticketCodingWalls`, `ticketTestWalls` public for test access

**Changes in `tests/test_scriptorium.nim`:**
- Added test verifying stall-check test wall time accumulates into `ticketTestWalls`
- Added test verifying all timing state is cleaned up when a ticket is reopened
```

### Agent Stdout Tail
```text
um.nim`:**\n- Added test verifying stall-check test wall time accumulates into `ticketTestWalls`\n- Added test verifying all timing state is cleaned up when a ticket is reopened","stop_reason":"end_turn","session_id":"7f56c3e7-c96d-4e69-88f6-e63c9f8639c3","total_cost_usd":2.2409256999999996,"usage":{"input_tokens":59,"cache_creation_input_tokens":56792,"cache_read_input_tokens":2712702,"output_tokens":13503,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":56792,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":59,"outputTokens":13503,"cacheReadInputTokens":2712702,"cacheCreationInputTokens":56792,"webSearchRequests":0,"costUSD":2.0491709999999994,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":48,"outputTokens":7707,"cacheReadInputTokens":889642,"cacheCreationInputTokens":51366,"webSearchRequests":0,"costUSD":0.19175470000000003,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"9e83158b-4ec1-4d02-a9db-5235bbb594d0"}
```

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0036-timing-capture-infrastructure/.scriptorium/logs/0036/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0036-timing-capture-infrastructure/.scriptorium/logs/0036/attempt-02.last_message.txt\n
### Agent Last Message
```text
`submit_pr` called successfully. The orchestrator responded with "Merge request enqueued."

Summary of changes:
- Initialized `ticketCodingWalls` and `ticketTestWalls` to 0.0 on ticket assignment in `assignOldestOpenTicket`
- Accumulated test wall time during stall retry test runs in `executeAssignedTicket`
- Accumulated merge queue test wall time into the cumulative total in `processMergeQueue`
- Cleaned up all timing state (`ticketStartTimes`, `ticketAttemptCounts`, `ticketCodingWalls`, `ticketTestWalls`) on reopen, park, and done transitions
- Exported timing tables (`*` visibility) for downstream use
- Added two tests: one verifying test wall time accumulation on stall, one verifying timing state cleanup on reopen
```

### Agent Stdout Tail
```text
`\n- Accumulated merge queue test wall time into the cumulative total in `processMergeQueue`\n- Cleaned up all timing state (`ticketStartTimes`, `ticketAttemptCounts`, `ticketCodingWalls`, `ticketTestWalls`) on reopen, park, and done transitions\n- Exported timing tables (`*` visibility) for downstream use\n- Added two tests: one verifying test wall time accumulation on stall, one verifying timing state cleanup on reopen","stop_reason":"end_turn","session_id":"7b3ab026-9de5-4d65-888b-5b13e2a1ff37","total_cost_usd":0.87213225,"usage":{"input_tokens":43,"cache_creation_input_tokens":33417,"cache_read_input_tokens":1077872,"output_tokens":4965,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":33417,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":43,"outputTokens":4965,"cacheReadInputTokens":1077872,"cacheCreationInputTokens":33417,"webSearchRequests":0,"costUSD":0.87213225,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"fbf13284-d7de-41ee-9f48-4b2f33c0ff11"}
```
