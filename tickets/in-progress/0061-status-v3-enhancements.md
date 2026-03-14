# Status Command V3 Enhancements

**Area:** status-worktrees

## Problem

The `scriptorium status` command (in `src/scriptorium.nim` `cmdStatus`) currently shows only basic ticket counts and active agent info. V3 §17 requires additional information: elapsed time for in-progress tickets, last N completed tickets with outcomes, and cumulative first-attempt success rate.

## Requirements

### Elapsed time for in-progress ticket
- Show how long the current in-progress ticket has been running.
- Parse the ticket's `**Worktree:**` and check worktree creation time, or use the ticket's move-to-in-progress commit timestamp.
- Format as human-readable duration (e.g., `12m`, `1h23m`).

### Last N completed tickets
- Show the last 5 (default) completed tickets from `tickets/done/`.
- For each, show: ticket ID, outcome (`done`, `reopened`, `parked`), and wall time.
- Parse wall time from the `## Metrics` section (`wall_time_seconds` field) in done ticket markdown.
- Parse outcome from the `outcome` field in metrics.

### First-attempt success rate
- Calculate from all done tickets: percentage where `attempt_count` is 1.
- Display as: `First-attempt success: 85% (17/20)`.

### Existing output preserved
- All current status output (ticket counts, active agent info) must remain unchanged.
- New information appended after existing output.

## Acceptance Criteria

- `scriptorium status` shows elapsed time for in-progress tickets.
- Shows last 5 completed tickets with outcome and wall time.
- Shows cumulative first-attempt success rate.
- Existing status output unchanged.
- `make test` passes.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0061-status-v3-enhancements

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0061-status-v3-enhancements/.scriptorium/logs/0061/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0061-status-v3-enhancements/.scriptorium/logs/0061/attempt-01.last_message.txt\n
### Agent Last Message
```text
ptorium/shared_state.nim`** — Added `DoneTicketSummary` and `InProgressTicketElapsed` types, extended `OrchestratorStatus` with `inProgressElapsed`, `recentDoneTickets`, `firstAttemptSuccessCount`, and `totalDoneWithAttempts` fields.

2. **`src/scriptorium/ticket_metadata.nim`** — Added `parseMetricField` (extracts metric values from `## Metrics` sections) and `formatDuration` (formats seconds as `12m`, `1h23m`, etc.).

3. **`src/scriptorium/ticket_assignment.nim`** — Extended `readOrchestratorStatus` to collect elapsed time for in-progress tickets (from worktree creation time), parse done ticket metrics, compute last 5 completed tickets, and calculate first-attempt success rate.

4. **`src/scriptorium.nim`** — Updated `cmdStatus` to display elapsed time per in-progress ticket, recent completed tickets with outcome/wall time, and cumulative first-attempt success rate.

5. **`tests/test_scriptorium.nim`** — Added test suites for `parseMetricField` (6 tests) and `formatDuration` (3 tests).

`make test` passes cleanly. The `submit_pr` MCP tool is not available in this environment — the orchestrator will need to pick up this commit from the `scriptorium/ticket-0061` branch.
```

### Agent Stdout Tail
```text
ke test` passes cleanly. The `submit_pr` MCP tool is not available in this environment — the orchestrator will need to pick up this commit from the `scriptorium/ticket-0061` branch.","stop_reason":"end_turn","session_id":"1a2408bb-5bac-4193-b9a0-f3a76bf95dab","total_cost_usd":1.5055972000000002,"usage":{"input_tokens":39,"cache_creation_input_tokens":43893,"cache_read_input_tokens":1473803,"output_tokens":11100,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":43893,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":39,"outputTokens":11100,"cacheReadInputTokens":1473803,"cacheCreationInputTokens":43893,"webSearchRequests":0,"costUSD":1.28892775,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":125,"outputTokens":8852,"cacheReadInputTokens":1004032,"cacheCreationInputTokens":57505,"webSearchRequests":0,"costUSD":0.21666944999999999,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"464d5e0a-8da8-413a-bf35-1aad96e8cf28"}
```

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0061-status-v3-enhancements/.scriptorium/logs/0061/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0061-status-v3-enhancements/.scriptorium/logs/0061/attempt-02.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` tool returned "Merge request enqueued." successfully. 

The ticket work was already complete from the previous attempt - the implementation adds:
1. **Elapsed time** for in-progress tickets (parsed from worktree creation time)
2. **Last 5 completed tickets** with outcome and wall time (from `## Metrics` section)
3. **First-attempt success rate** percentage (from `attempt_count` metric)

All existing status output is preserved, and tests pass.
```

### Agent Stdout Tail
```text
st enqueued.\" successfully. \n\nThe ticket work was already complete from the previous attempt - the implementation adds:\n1. **Elapsed time** for in-progress tickets (parsed from worktree creation time)\n2. **Last 5 completed tickets** with outcome and wall time (from `## Metrics` section)\n3. **First-attempt success rate** percentage (from `attempt_count` metric)\n\nAll existing status output is preserved, and tests pass.","stop_reason":"end_turn","session_id":"68c57220-473e-48d1-83a2-930160e668eb","total_cost_usd":0.4816305,"usage":{"input_tokens":20,"cache_creation_input_tokens":25724,"cache_read_input_tokens":509161,"output_tokens":2647,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":25724,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":20,"outputTokens":2647,"cacheReadInputTokens":509161,"cacheCreationInputTokens":25724,"webSearchRequests":0,"costUSD":0.4816305,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"efa194ea-0a1a-4e22-9dcb-c100780d98d0"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 2m9s
