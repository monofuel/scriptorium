# Enforce staggered start rule for coding agents

**Area:** parallel-execution

## Problem

The orchestrator parallel path (`maxAgents > 1`) passes `slotsAvailable` to
`assignOpenTickets` and starts ALL returned assignments in one tick
(`src/scriptorium/orchestrator.nim` lines 291–296). The area spec requires
"at most 1 new coding agent per tick" to avoid burst-spawning.

## Task

In `runOrchestratorMainLoop` (file `src/scriptorium/orchestrator.nim`), change
the parallel coding agent start block (step 6) so that:

1. Call `assignOpenTickets(repoPath, 1)` instead of
   `assignOpenTickets(repoPath, slotsAvailable)` — this assigns at most one
   ticket per tick while still respecting area independence and dependency
   checks.
2. Keep the existing stall/submission handling, prediction, and
   `startCodingAgentAsync` call unchanged.
3. The `slotsAvailable > 0` guard remains so no assignment is attempted when
   the pool is full.

This is a one-line change: replace the second argument from `slotsAvailable`
to `1`.

Verify `make test` passes after the change.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0089-enforce-staggered-start-rule-for-coding-agents
