# Status, Worktree Visibility, And Managed Paths

Covers `scriptorium status`, `scriptorium worktrees`, and deterministic managed path layout.

## Scope

- `scriptorium status` reports:
  - Open, in-progress, and done ticket counts.
  - Active ticket id/path/branch/worktree.
  - Elapsed time for the current in-progress ticket.
  - Last N completed tickets (default 5) with outcome and wall time.
  - Cumulative first-attempt success rate.
  - `Active Agent: none` when no active ticket.
- Active ticket resolution: prefer active merge-queue item, fall back to first in-progress ticket worktree.
- `scriptorium worktrees` lists active in-progress ticket worktrees with path, ticket id, and branch.
- No in-progress worktrees prints: `scriptorium: no active ticket worktrees`.
- Managed repository state lives in deterministic per-repo paths under `/tmp/scriptorium/`.

## Spec References

- Section 15: Status And Worktree Visibility.
