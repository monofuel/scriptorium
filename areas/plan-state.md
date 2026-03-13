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
- Area IDs derived from area markdown filenames.
- Area-to-ticket linkage: `**Area:** <area-id>` in ticket markdown.
- Ticket assignment:
  - Move oldest open ticket to `tickets/in-progress/`.
  - Deterministic ticket branch: `scriptorium/ticket-<id>`.
  - Deterministic managed code worktree path under `/tmp/scriptorium/.../worktrees/tickets/`.
  - Record `**Worktree:** <absolute-path>` in ticket markdown.
  - Parallel assignment (V5): multiple tickets assigned per tick when they touch independent areas; same-area tickets serialized (detail in parallel-execution area).
- Active merge queue metadata: ticket path, ticket id, branch, worktree, summary.
- Ticket dependency cycle detection (V7, §29):
  - After the manager writes new tickets, the orchestrator must validate the dependency graph remains acyclic.
  - Build a directed graph from all open and in-progress tickets using `**Depends:** <id-list>` fields.
  - Check for strongly connected components (cycles) using Tarjan's or DFS-based algorithm.
  - If a cycle is detected, log error: `ticket <id>: dependency cycle detected (<id> -> <id> -> ... -> <id>)`.
  - Periodic scan on each tick identifies tickets permanently blocked by cycles, logged as warnings.
  - Non-circular dependency checking (`dependenciesSatisfied`) continues to work as before.
  - Unit tests must cover: simple cycle (A->B->A), multi-node cycle (A->B->C->A), no cycle, self-dependency.

## Spec References

- Section 4: Planning Artifacts And State Model.
- Section 22: Commit Health Cache (V4, `health/cache.json` layout).
- Section 23: Parallel Ticket Assignment (V5, detail in parallel-execution area).
- Section 29: Ticket Dependency Cycle Detection (V7).
