# Restructured Orchestrator Tick For Interleaved Manager/Coder Execution

**Area:** parallel-execution

**Depends:** 0069

## Problem

V13 §30 requires a restructured tick where managers and coders are interleaved rather than strictly sequential. The current tick runs architect → manager (blocking batch) → coding → merge. The new tick must poll completions first, then start both managers and coders based on available slots.

## Requirements

Refactor the tick loop in `orchestrator.nim` to follow this order:

1. **Poll completed agents** (managers + coders) via `checkCompletedAgents()`.
   - For completed managers: acquire plan lock, write tickets via `writeTicketsForArea()`, commit, release. Log results.
   - For completed coders: handle as before (move ticket, queue merge, etc).
2. **Check backoff / health**: Rate limit backoff, master health check.
3. **Run architect** (sequential, if spec changed). Must complete before managers are spawned.
4. **Read areas needing tickets** (brief plan lock to snapshot area content).
5. **For each area needing tickets**, if slots available in the shared pool, start a manager agent.
6. **For each assignable ticket**, if slots available, start a coding agent.
7. **Process at most one merge-queue item**.
8. **Sleep**.

Additional requirements:
- Managers prioritized over coders when slots are scarce (step 5 runs before step 6).
- If a manager finishes and produces tickets while another manager is running, those tickets can be assigned to coding agents on the next tick.
- When `maxAgents` is 1, behavior collapses to sequential execution as before.
- Remove the serial-mode special path if it can be unified with the parallel path.
- `make test` must pass. Update existing orchestrator tests to match new tick structure.

## Notes

- This ticket restructures the orchestrator tick loop in `src/scriptorium/orchestrator.nim`.
- Depends on the shared agent pool (0068) and per-area concurrent managers (0069) being in place.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0071-restructured-orchestrator-tick

## Prediction
- predicted_difficulty: hard
- predicted_duration_minutes: 32
- reasoning: Major refactor of the orchestrator tick loop touching core control flow in orchestrator.nim, requiring reordering of manager/coder interleaving logic, unifying serial/parallel paths, and updating existing orchestrator tests — high integration risk with concurrency semantics likely requiring 2+ attempts.
