# 0090 Enrich tick summary line with running agents and stuck count

**Area:** orchestrator

## Problem

The tick summary line at `orchestrator.nim:327` logs architect, manager, coding, merge status and open/in-progress/done counts. It is missing:

- Running agent count and max (e.g., `agents=2/4`) — critical for understanding slot utilization.
- Stuck ticket count — tickets parked after 3 failures are invisible in the summary.

The area spec says the tick summary should capture "full system state."

## Task

In `src/scriptorium/orchestrator.nim`, enrich the tick summary line (around line 326-328) to include:

1. `agents={running}/{maxAgents}` — current running agent count vs configured max.
2. `stuck={stuckCount}` — number of tickets in `tickets/stuck/`.

Read stuck count from `readOrchestratorStatus` (which already reads the plan worktree) or add stuck counting to the existing `ticketCounts` read. The `OrchestratorStatus` type in `shared_state.nim` may need a `stuckTickets` field if one doesn't exist.

Example output:

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0093-0090-enrich-tick-summary-line-with-running-agents-and-stuck-count

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 11
- reasoning: Small additive change to a log line in orchestrator.nim plus possibly adding a field to shared_state.nim, minimal logic and low integration risk.
