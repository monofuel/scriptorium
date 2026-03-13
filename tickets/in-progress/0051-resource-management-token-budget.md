# Resource Management — Token Budget Tracking

**Area:** parallel-execution

## Problem

The V5 spec (§26) requires monitoring cumulative `stdout_bytes` across all running agents and pausing new ticket assignment when the optional `concurrency.tokenBudgetMB` is exceeded.

## Requirements

1. Track aggregate `stdout_bytes` across all running agents as a session-level counter.
   - The per-ticket `ticketStdoutBytes` table already exists — sum all values for the session total.
2. Before assigning new tickets, check if `concurrency.tokenBudgetMB` is set and if cumulative `stdout_bytes` exceeds the budget:
   - If exceeded: log `resource limit: token budget exhausted (<used>MB/<budget>MB), pausing new assignments`.
   - Skip new ticket assignment but allow running agents to complete normally.
3. A `tokenBudgetMB` of 0 means unlimited (no budget enforcement).
4. Add unit tests verifying:
   - No budget enforcement when `tokenBudgetMB = 0`.
   - Assignment paused when budget exceeded.
   - Running agents not interrupted when budget exceeded.

## Dependencies

- Ticket 0045 (concurrency config keys — provides `tokenBudgetMB`)
- Ticket 0049 (non-blocking tick — provides agent pool context)

## Acceptance Criteria

- `make test` passes with new tests.
- Budget enforcement is logged clearly.
- No impact when `tokenBudgetMB` is 0 or unset.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0051-resource-management-token-budget

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 20
- reasoning: Straightforward aggregation of an existing per-ticket counter with a simple threshold check before assignment, plus basic unit tests — no new data structures or complex concurrency logic required.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0051-resource-management-token-budget/.scriptorium/logs/0051/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0051-resource-management-token-budget/.scriptorium/logs/0051/attempt-01.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` MCP tool is not available in the current environment. All changes are committed on branch `scriptorium/ticket-0051`. Here's a summary of what was done:

**Changes made:**

1. **`src/scriptorium/orchestrator.nim`** — Added two new procs:
   - `getSessionStdoutBytes*()` — sums all `ticketStdoutBytes` values for the session total
   - `isTokenBudgetExceeded*(tokenBudgetMB: int)` — returns true and logs a message when cumulative stdout bytes exceed the budget; returns false when budget is 0 (unlimited)
   
   Added budget checks before ticket assignment in both:
   - Serial mode (line ~3325): skips `executeOldestOpenTicket` when budget exceeded
   - Parallel mode (line ~3342): skips `assignOpenTickets` when budget exceeded

2. **`tests/test_scriptorium.nim`** — Added "token budget tracking" test suite with 7 tests:
   - Session stdout bytes summing
   - No enforcement when `tokenBudgetMB = 0` or negative
   - Assignment paused when budget exceeded
   - Assignment allowed when under budget
   - Running agents not interrupted when budget exceeded

All tests pass via `make test`.
```

### Agent Stdout Tail
```text
ignOpenTickets` when budget exceeded\n\n2. **`tests/test_scriptorium.nim`** — Added \"token budget tracking\" test suite with 7 tests:\n   - Session stdout bytes summing\n   - No enforcement when `tokenBudgetMB = 0` or negative\n   - Assignment paused when budget exceeded\n   - Assignment allowed when under budget\n   - Running agents not interrupted when budget exceeded\n\nAll tests pass via `make test`.","stop_reason":"end_turn","session_id":"fbe59c1b-dd82-4ff7-b6d8-f5e37407e6da","total_cost_usd":0.8913859999999999,"usage":{"input_tokens":32,"cache_creation_input_tokens":32890,"cache_read_input_tokens":971127,"output_tokens":8004,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":32890,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":32,"outputTokens":8004,"cacheReadInputTokens":971127,"cacheCreationInputTokens":32890,"webSearchRequests":0,"costUSD":0.8913859999999999,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"81b75748-5f56-4b9c-8754-e37eff995e00"}
```

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0051-resource-management-token-budget/.scriptorium/logs/0051/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0051-resource-management-token-budget/.scriptorium/logs/0051/attempt-02.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` MCP tool returned "Merge request enqueued." successfully. The ticket work is complete:

- **Token budget tracking** added to `orchestrator.nim` — sums all `ticketStdoutBytes` values for session total and checks against `concurrency.tokenBudgetMB` before assigning new tickets
- **Budget enforcement** logs `resource limit: token budget exhausted (<used>MB/<budget>MB), pausing new assignments` when exceeded
- **No impact** when `tokenBudgetMB` is 0 or unset (unlimited)
- **Unit tests** added covering: no enforcement at 0, assignment paused when exceeded, running agents not interrupted, session byte summation
```

### Agent Stdout Tail
```text
hecks against `concurrency.tokenBudgetMB` before assigning new tickets\n- **Budget enforcement** logs `resource limit: token budget exhausted (<used>MB/<budget>MB), pausing new assignments` when exceeded\n- **No impact** when `tokenBudgetMB` is 0 or unset (unlimited)\n- **Unit tests** added covering: no enforcement at 0, assignment paused when exceeded, running agents not interrupted, session byte summation","stop_reason":"end_turn","session_id":"6f2da8d5-849e-4b6a-b5da-4bd11eead358","total_cost_usd":0.5777132500000001,"usage":{"input_tokens":31,"cache_creation_input_tokens":24527,"cache_read_input_tokens":655329,"output_tokens":3864,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":24527,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":31,"outputTokens":3864,"cacheReadInputTokens":655329,"cacheCreationInputTokens":24527,"webSearchRequests":0,"costUSD":0.5777132500000001,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"67247068-acdd-48f8-b634-9f999a4641e2"}
```

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 20
- reasoning: Straightforward aggregation of an existing per-ticket counter with a simple threshold check before assignment, plus basic unit tests — no new data structures or complex concurrency logic required.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0051-resource-management-token-budget/.scriptorium/logs/0051/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0051-resource-management-token-budget/.scriptorium/logs/0051/attempt-01.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` MCP tool is not available in my tool set. All changes are committed on branch `scriptorium/ticket-0051`. Here's what was implemented:

**Changes:**

1. **`src/scriptorium/orchestrator.nim`** — Added two procs:
   - `getSessionStdoutBytes*()` — sums all `ticketStdoutBytes` values for the session total
   - `isTokenBudgetExceeded*(tokenBudgetMB: int)` — returns true and logs when cumulative stdout bytes exceed budget; returns false when budget is 0 (unlimited)
   
   Added budget check before ticket assignment in both serial and parallel modes — skips new assignments when exceeded, but allows running agents to complete normally.

2. **`tests/test_scriptorium.nim`** — Added 7 tests covering: session byte summation, no enforcement at 0 or negative, assignment paused when exceeded, allowed when under budget, running agents not interrupted.

All tests pass via `make test`. I'm unable to call the `submit_pr` MCP tool as it's not available in my current environment.
```

### Agent Stdout Tail
```text
skips new assignments when exceeded, but allows running agents to complete normally.\n\n2. **`tests/test_scriptorium.nim`** — Added 7 tests covering: session byte summation, no enforcement at 0 or negative, assignment paused when exceeded, allowed when under budget, running agents not interrupted.\n\nAll tests pass via `make test`. I'm unable to call the `submit_pr` MCP tool as it's not available in my current environment.","stop_reason":"end_turn","session_id":"eec46c92-7fb4-4998-a497-8ce4df99bed4","total_cost_usd":0.6622295,"usage":{"input_tokens":25,"cache_creation_input_tokens":27584,"cache_read_input_tokens":656559,"output_tokens":6457,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":27584,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":25,"outputTokens":6457,"cacheReadInputTokens":656559,"cacheCreationInputTokens":27584,"webSearchRequests":0,"costUSD":0.6622295,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"41601284-307b-4588-8092-4b3466dfefbb"}
```

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0051-resource-management-token-budget/.scriptorium/logs/0051/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0051-resource-management-token-budget/.scriptorium/logs/0051/attempt-02.last_message.txt\n
### Agent Last Message
```text
`submit_pr` returned "Merge request enqueued." successfully. The ticket is complete:

- **Token budget tracking** added to `orchestrator.nim` with `getSessionStdoutBytes` and `isTokenBudgetExceeded` procs
- Budget checks before ticket assignment in both serial and parallel tick paths
- No enforcement when `tokenBudgetMB` is 0 or unset
- 7 unit tests covering all acceptance criteria
- All tests pass via `make test`
```

### Agent Stdout Tail
```text
ned \"Merge request enqueued.\" successfully. The ticket is complete:\n\n- **Token budget tracking** added to `orchestrator.nim` with `getSessionStdoutBytes` and `isTokenBudgetExceeded` procs\n- Budget checks before ticket assignment in both serial and parallel tick paths\n- No enforcement when `tokenBudgetMB` is 0 or unset\n- 7 unit tests covering all acceptance criteria\n- All tests pass via `make test`","stop_reason":"end_turn","session_id":"c3cf6825-5ba8-4d63-b978-53a7f3d9a1f3","total_cost_usd":0.48528725000000006,"usage":{"input_tokens":26,"cache_creation_input_tokens":22151,"cache_read_input_tokens":543527,"output_tokens":2998,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":22151,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":26,"outputTokens":2998,"cacheReadInputTokens":543527,"cacheCreationInputTokens":22151,"webSearchRequests":0,"costUSD":0.48528725000000006,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"5d24ea85-6a89-4053-a06c-6658e220c74c"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 50s

## Merge Queue Failure
- Summary: Add token budget tracking to pause new assignments when stdout bytes exceed limit. Added getSessionStdoutBytes and isTokenBudgetExceeded procs, budget checks in serial and parallel tick paths, and 7 unit tests.\n- Failed gate: git merge --ff-only master\n
### Merge Output
```text
Auto-merging src/scriptorium/orchestrator.nim
Auto-merging tests/test_scriptorium.nim
Merge made by the 'ort' strategy.
 scriptorium.json                 |  4 ++++
 src/scriptorium/config.nim       | 13 +++++++++++++
 src/scriptorium/orchestrator.nim |  6 ++----
 tests/test_scriptorium.nim       | 22 ++++++++++++++++++++++
 4 files changed, 41 insertions(+), 4 deletions(-)
```

### Quality Check Output
```text
error: Your local changes to the following files would be overwritten by merge:
	src/scriptorium/orchestrator.nim
	tests/test_scriptorium.nim
Please commit your changes or stash them before you merge.
Aborting
Updating 523c6a3..10f3089
```

## Metrics
- wall_time_seconds: 848
- coding_wall_seconds: 461
- test_wall_seconds: 76
- attempt_count: 2
- outcome: reopened
- failure_reason: test_failure
- model: claude-opus-4-6
- stdout_bytes: 708084

## Post-Analysis
- actual_difficulty: hard
- prediction_accuracy: underestimated
- brief_summary: Predicted easy, actual was hard with 2 attempt(s) in 14m8s.

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 35
- reasoning: While the logic is simple (summing existing counters and adding a threshold check), the prior run failed due to merge conflicts in orchestrator.nim and test files, requiring a second attempt and careful conflict resolution — suggesting moderate integration complexity.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0051-resource-management-token-budget/.scriptorium/logs/0051/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0051-resource-management-token-budget/.scriptorium/logs/0051/attempt-01.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` MCP tool is not available in this environment. All changes are committed on branch `scriptorium/ticket-0051`. Here's what was implemented:

**Changes:**

1. **`src/scriptorium/orchestrator.nim`** — Added `getSessionStdoutBytes()` (sums all `ticketStdoutBytes` values) and `isTokenBudgetExceeded(tokenBudgetMB)` (checks against budget, returns false when 0/negative). Added budget check before ticket assignment in both serial and parallel tick paths — skips new assignments when exceeded but allows running agents to complete.

2. **`tests/test_scriptorium.nim`** — Added 7 tests: session byte summation, no enforcement at 0 or negative, assignment paused when exceeded, under budget allowed, running agents not interrupted.

All tests pass via `make test`. I'm unable to call the `submit_pr` MCP tool as it's not available in this environment.
```

### Agent Stdout Tail
```text
and parallel tick paths — skips new assignments when exceeded but allows running agents to complete.\n\n2. **`tests/test_scriptorium.nim`** — Added 7 tests: session byte summation, no enforcement at 0 or negative, assignment paused when exceeded, under budget allowed, running agents not interrupted.\n\nAll tests pass via `make test`. I'm unable to call the `submit_pr` MCP tool as it's not available in this environment.","stop_reason":"end_turn","session_id":"d28ea7a5-4327-4f1f-97a7-399debdfa3f0","total_cost_usd":0.71495375,"usage":{"input_tokens":26,"cache_creation_input_tokens":29681,"cache_read_input_tokens":740235,"output_tokens":6368,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":29681,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":26,"outputTokens":6368,"cacheReadInputTokens":740235,"cacheCreationInputTokens":29681,"webSearchRequests":0,"costUSD":0.71495375,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"a7f30ce5-e3cd-4bbf-809e-b0c0d9d1edcf"}
```
