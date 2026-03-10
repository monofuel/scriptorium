# Planning Artifacts And State Model Baseline

**Area:** plan-state
**Status:** done

## Summary

The plan branch file layout, ticket lifecycle, and managed worktree paths are fully implemented and tested.

## What Exists

- Authoritative plan branch layout enforced in `orchestrator.nim`:
  - `spec.md`, `areas/*.md`
  - `tickets/open/*.md`, `tickets/in-progress/*.md`, `tickets/done/*.md`
  - `queue/merge/pending/*.md`, `queue/merge/active.md`
- `queue/merge/` created lazily by orchestrator queue initialization, not by `--init`.
- Tickets exist in exactly one state directory at a time; transitions via single orchestrator commits.
- Ticket IDs: monotonic, zero-padded filenames.
- Merge queue item IDs: monotonic, zero-padded filenames.
- Area IDs derived from area markdown filenames.
- Area-to-ticket linkage: `**Area:** <area-id>` in ticket markdown.
- Ticket assignment:
  - Moves oldest open ticket to `tickets/in-progress/`.
  - Deterministic ticket branch: `scriptorium/ticket-<id>`.
  - Deterministic managed code worktree path under `/tmp/scriptorium/.../worktrees/tickets/`.
  - Records `**Worktree:** <absolute-path>` in ticket markdown.
- Active merge queue metadata stores: ticket path, ticket id, branch, worktree, summary.
- Managed path functions: `managedRepoRootPath`, `managedPlanWorktreePath`, `managedMasterWorktreePath`, `managedTicketWorktreeRootPath`.
- Tests: `test_scriptorium.nim`, `integration_orchestrator_queue.nim`.
