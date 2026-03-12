# Session Summary On Shutdown

**Area:** observability

## Description

On orchestrator shutdown (signal or idle exit), log exactly two INFO-level summary lines with session-wide statistics.

## Current State

The orchestrator logs `shutdown: signal <n> received` on signal but does not track or log any session-wide statistics. No session start time, tick count, or ticket outcome counters are maintained.

## Requirements

- Track session-level counters throughout orchestrator lifetime:
  - Session start time (for uptime calculation).
  - Total ticks executed.
  - Tickets completed (moved to done).
  - Tickets reopened.
  - Tickets parked.
  - Merge queue items processed.
  - Per-ticket wall times, coding wall times, test wall times (for averages).
  - First-attempt success count (for percentage calculation).

- On shutdown (signal handler or idle exit), log exactly two INFO-level lines:
  - Counts line: `session summary: uptime=1h23m ticks=47 tickets_completed=3 tickets_reopened=1 tickets_parked=0 merge_queue_processed=3`
  - Averages line: `session summary: avg_ticket_wall=5m12s avg_coding_wall=4m02s avg_test_wall=38s first_attempt_success=75%`

- If no tickets completed, averages show `n/a` or `0`.
- Uptime and durations are human-readable.

## Implementation Notes

- Add a session stats object (or fields on existing orchestrator state) initialized at startup.
- Increment counters at relevant points: ticket completion, reopen, parking, merge processing.
- Store per-ticket timing data for average calculations.
- Call a `logSessionSummary()` proc from the shutdown path (both signal handler and idle exit).
- Reuse the human-readable duration formatter.

## Spec References

- Section 16: Session Summary On Shutdown (V3).

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0035-session-summary-on-shutdown
