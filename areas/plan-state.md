# Planning Artifacts And State Model

Covers the plan branch file layout, ticket lifecycle, and managed worktree paths.

## Scope

- Authoritative plan branch layout:
  - `spec.md`
  - `areas/*.md`
  - `tickets/open/*.md`, `tickets/in-progress/*.md`, `tickets/done/*.md`
  - `queue/merge/pending/*.md`, `queue/merge/active.md`
  - `health/cache.json`
- `queue/merge/` created lazily by orchestrator, not by `--init`.
- Ticket state: exactly one state directory at a time, transitions via single orchestrator commits.
- Ticket IDs: monotonic, zero-padded filenames.
- Merge queue item IDs: monotonic, zero-padded filenames.
- Areas are persistent ownership zones that evolve with the spec, not one-shot artifacts; the architect updates or creates area files whenever `spec.md` changes, and the manager re-tickets areas whose content has changed.
- Area IDs derived from area markdown filenames.
- Area-to-ticket linkage: `**Area:** <area-id>` in ticket markdown.
- Ticket assignment:
  - Move oldest open ticket to `tickets/in-progress/`.
  - Deterministic ticket branch: `scriptorium/ticket-<id>`.
  - Deterministic managed code worktree path under `/tmp/scriptorium/.../worktrees/tickets/`.
  - Record `**Worktree:** <absolute-path>` in ticket markdown.
  - Parallel assignment: multiple tickets assigned per tick when they touch independent areas; same-area tickets serialized (detail in parallel-execution area).
- Active merge queue metadata: ticket path, ticket id, branch, worktree, summary.

## Spec References

- Section 4: Planning Artifacts And State Model.
- Section 3: Orchestrator Run Loop (`health/cache.json` layout).
- Section 11: Parallel Ticket Assignment And Concurrency (detail in parallel-execution area).
