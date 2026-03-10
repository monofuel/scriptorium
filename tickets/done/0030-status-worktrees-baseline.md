# Status, Worktree Visibility, And Managed Paths Baseline

**Area:** status-worktrees
**Status:** done

## Summary

`scriptorium status`, `scriptorium worktrees`, and deterministic managed path layout are fully implemented and tested.

## What Exists

- `scriptorium status` reports:
  - Open, in-progress, and done ticket counts.
  - Active ticket id, path, branch, and worktree.
  - Prints `Active Agent: none` when no active ticket.
- Active ticket resolution: prefers active merge-queue item, falls back to first in-progress ticket worktree.
- `scriptorium worktrees` lists active in-progress ticket worktrees with path, ticket id, and branch.
- No in-progress worktrees prints: `scriptorium: no active ticket worktrees`.
- Managed repository state in deterministic per-repo paths under `/tmp/scriptorium/`:
  - `managedRepoRootPath(repoPath)`: hashed per-repo root.
  - `managedWorktreeRootPath()`: `./worktrees/` subdirectory.
  - `managedPlanWorktreePath()`: `./worktrees/plan`.
  - `managedMasterWorktreePath()`: `./worktrees/master`.
  - `managedTicketWorktreeRootPath()`: `./worktrees/tickets/`.
  - `isManagedWorktreePath()`: validates if a path is within managed root.
- Repository lock state managed under same deterministic path.
- Tests: `test_scriptorium.nim`, `integration_orchestrator_queue.nim`.
