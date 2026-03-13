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
