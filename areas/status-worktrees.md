# Status, Worktree Visibility, And Managed Paths

Covers `scriptorium status`, `scriptorium worktrees`, and deterministic managed path layout.

## Scope

- `scriptorium status` reports:
  - Open, in-progress, and done ticket counts.
  - Active ticket id/path/branch/worktree.
  - `Active Agent: none` when no active ticket.
- Active ticket resolution: prefer active merge-queue item, fall back to first in-progress ticket worktree.
- `scriptorium worktrees` lists active in-progress ticket worktrees with path, ticket id, and branch.
- No in-progress worktrees prints: `scriptorium: no active ticket worktrees`.
- Managed repository state lives in deterministic per-repo paths under `/tmp/scriptorium/`.
- Managed state includes worktrees and repository lock state.
- Status command enhancement (V3):
  - Elapsed time for the current in-progress ticket (how long it has been running).
  - Last N completed tickets (default 5) with outcome (`done`, `reopened`, `parked`) and wall time.
  - Cumulative first-attempt success rate across all done tickets.
  - Existing status output (ticket counts, active ticket info) preserved.

## Spec References

- Section 8: Status, Worktree Visibility, And Managed Paths.
- Section 17: Status Command Enhancement (V3).
