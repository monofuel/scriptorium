# Observability And Orchestrator Logging

Tick summary lines, ticket lifecycle logging, and session summary on shutdown.

## Scope

- Tick summary line:
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

- Ticket lifecycle logging:
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
  - Review-related log points:
    - Review start: `ticket <id>: review started (model=<model>)`
    - Review approved: `ticket <id>: review approved`
    - Review approved with warnings: `ticket <id>: review approved with warnings`
    - Review changes requested: `ticket <id>: review requested changes (feedback="<summary>")`
    - Review stall: `ticket <id>: review agent stalled, defaulting to approve`
  - Pre-submit test gate log point:
    - `ticket <id>: submit_pr pre-check: <PASS|FAIL> (exit=<code>, wall=<duration>)`
  - Health cache log points:
    - `master health: cached healthy for <commit-hash>`
    - `master health: cached unhealthy for <commit-hash>`
  - Audit agent log points:
    - `audit: started (model=<model>, since=<last-audited-commit>)`
    - `audit: completed (report=<path>)`
    - `audit: triggered by spec change`
  - All lines include ticket ID for correlation (where applicable).
  - Durations are human-readable.

- Session summary on shutdown:
  - On shutdown (signal or idle exit), log exactly two INFO-level summary lines.
  - Counts line: `uptime`, `ticks`, `tickets_completed`, `tickets_reopened`, `tickets_parked`, `merge_queue_processed`.
  - Averages line: `avg_ticket_wall`, `avg_coding_wall`, `avg_test_wall`, `first_attempt_success` (percentage).
  - Example:
    - `session summary: uptime=1h23m ticks=47 tickets_completed=3 tickets_reopened=1 tickets_parked=0 merge_queue_processed=3`
    - `session summary: avg_ticket_wall=5m12s avg_coding_wall=4m02s avg_test_wall=38s first_attempt_success=75%`
  - If no tickets completed, averages show `n/a` or `0`.

## Spec References

- Section 14: Observability And Metrics.
- Section 8: Pre-Submit Test Gate.
- Section 9: Review Agent (review lifecycle logging).
- Section 19: Audit Agent (audit log points).
