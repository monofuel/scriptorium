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
