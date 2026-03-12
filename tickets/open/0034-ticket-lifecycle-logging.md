# Ticket Lifecycle Logging

**Area:** observability

## Description

Add INFO-level log lines for every ticket state transition with timing, enabling full ticket lifecycle correlation via ticket ID.

## Current State

Some lifecycle events are already logged:
- Coding agent start/complete (`logInfo` for starting and completing ticket).
- Stall detection and continuation (`logInfo` for stall, pre-retry test pass/fail).
- PR submission (`logInfo` for submit_pr call).
- Some merge queue warnings (recovery, parking).

Missing lifecycle log points:
- Ticket assignment (open -> in-progress).
- Coding agent start with model/attempt details.
- Merge queue entry with position.
- Merge start (make test running).
- Merge success with test duration.
- Merge failure with reason.
- Ticket completion (in-progress -> done) with total wall time and attempt count.
- Ticket reopen (in-progress -> open) with reason, attempts, total wall time.

## Requirements

Add INFO-level log lines at each of the following points:

- Assignment: `ticket <id>: open -> in-progress (assigned, worktree=<path>)`
- Coding agent start: `ticket <id>: coding agent started (model=<model>, attempt <n>/<max>)`
- Coding agent finish: `ticket <id>: coding agent finished (exit=<code>, wall=<duration>, stall=<bool>)`
- PR submission: `ticket <id>: submit_pr called (summary="<summary>")`
- Merge queue entry: `ticket <id>: merge queue entered (position=<n>)`
- Merge start: `ticket <id>: merge started (make test running)`
- Merge success: `ticket <id>: merge succeeded (test wall=<duration>)`
- Merge failure: `ticket <id>: merge failed (reason=<reason>)`
- Completion: `ticket <id>: in-progress -> done (total wall=<duration>, attempts=<n>)`
- Reopen: `ticket <id>: in-progress -> open (reopened, reason=<reason>, attempts=<n>, total wall=<duration>)`

Stall-related (verify existing, update format if needed):
- Stall detection: `ticket <id>: coding agent stalled (attempt <n>/<max>, no submit_pr)`
- Pre-retry test: `ticket <id>: make test before retry: <PASS|FAIL> (exit=<code>, wall=<duration>)`
- Continuation: `ticket <id>: continuation prompt sent (attempt <n>/<max>, test_status=<passing|failing>)`

All lines must include ticket ID for correlation. Durations must be human-readable.

## Implementation Notes

- Add log lines at the relevant state transition points in `orchestrator.nim`.
- For wall time tracking on assignment->completion, store assignment start time (e.g., in a table or on the ticket state) and compute duration at completion/reopen.
- Reuse the human-readable duration formatter from the tick summary ticket.
- Update existing stall-related log lines to match the required format if they differ.

## Spec References

- Section 14: Ticket Lifecycle Logging (V3).
