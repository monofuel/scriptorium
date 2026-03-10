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

## Spec References

- Section 8: Status, Worktree Visibility, And Managed Paths.
