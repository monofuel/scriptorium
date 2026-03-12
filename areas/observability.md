# Observability And Orchestrator Logging

V3 feature: tick summary lines, ticket lifecycle logging, and session summary on shutdown.

## Scope

- Tick summary line (§13):
  - At the end of each orchestrator tick, log a single INFO-level summary line capturing full system state.
  - Required fields:
    - `architect`: `no-op`, `updated`, or `skipped`.
    - `manager`: `no-op`, `updated`, or `skipped`.
    - `coding`: ticket ID + status (`running`, `stalled`, `submitted`, `failed`) + wall time, or `idle`.
    - `merge`: `idle`, `processing`, or ticket ID being merged.
    - `open` / `in-progress` / `done`: current ticket counts.
  - Example: `tick 42 summary: architect=no-op manager=no-op coding=0031(running, 3m12s) merge=idle open=2 in-progress=1 done=14`
  - Every tick produces exactly one summary line.
  - Wall times are human-readable (e.g., `3m12s`).

- Ticket lifecycle logging (§14):
  - INFO-level log line for every ticket state transition, with timing.
  - Required log points:
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
  - Stall-related log points:
    - Stall detection: `ticket <id>: coding agent stalled (attempt <n>/<max>, no submit_pr)`
    - Pre-retry test: `ticket <id>: make test before retry: <PASS|FAIL> (exit=<code>, wall=<duration>)`
    - Continuation: `ticket <id>: continuation prompt sent (attempt <n>/<max>, test_status=<passing|failing>)`
  - All lines include ticket ID for correlation.
  - Durations are human-readable.

- Session summary on shutdown (§16):
  - On shutdown (signal or idle exit), log exactly two INFO-level summary lines.
  - Counts line: `uptime`, `ticks`, `tickets_completed`, `tickets_reopened`, `tickets_parked`, `merge_queue_processed`.
  - Averages line: `avg_ticket_wall`, `avg_coding_wall`, `avg_test_wall`, `first_attempt_success` (percentage).
  - Example:
    - `session summary: uptime=1h23m ticks=47 tickets_completed=3 tickets_reopened=1 tickets_parked=0 merge_queue_processed=3`
    - `session summary: avg_ticket_wall=5m12s avg_coding_wall=4m02s avg_test_wall=38s first_attempt_success=75%`
  - If no tickets completed, averages show `n/a` or `0`.

## V3 Known Limitations

- All metrics are stored in logs and plan-branch markdown only — no external dashboards or time-series storage.
- Session summary averages are per-session only, not cumulative across sessions.

## Spec References

- Section 13: Tick Summary Line (V3).
- Section 14: Ticket Lifecycle Logging (V3).
- Section 16: Session Summary On Shutdown (V3).
