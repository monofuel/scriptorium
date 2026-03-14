# Status Command V3 Enhancements

**Area:** status-worktrees

## Problem

The `scriptorium status` command (in `src/scriptorium.nim` `cmdStatus`) currently shows only basic ticket counts and active agent info. V3 §17 requires additional information: elapsed time for in-progress tickets, last N completed tickets with outcomes, and cumulative first-attempt success rate.

## Requirements

### Elapsed time for in-progress ticket
- Show how long the current in-progress ticket has been running.
- Parse the ticket's `**Worktree:**` and check worktree creation time, or use the ticket's move-to-in-progress commit timestamp.
- Format as human-readable duration (e.g., `12m`, `1h23m`).

### Last N completed tickets
- Show the last 5 (default) completed tickets from `tickets/done/`.
- For each, show: ticket ID, outcome (`done`, `reopened`, `parked`), and wall time.
- Parse wall time from the `## Metrics` section (`wall_time_seconds` field) in done ticket markdown.
- Parse outcome from the `outcome` field in metrics.

### First-attempt success rate
- Calculate from all done tickets: percentage where `attempt_count` is 1.
- Display as: `First-attempt success: 85% (17/20)`.

### Existing output preserved
- All current status output (ticket counts, active agent info) must remain unchanged.
- New information appended after existing output.

## Acceptance Criteria

- `scriptorium status` shows elapsed time for in-progress tickets.
- Shows last 5 completed tickets with outcome and wall time.
- Shows cumulative first-attempt success rate.
- Existing status output unchanged.
- `make test` passes.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0061-status-v3-enhancements
