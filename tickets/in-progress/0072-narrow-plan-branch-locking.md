# Narrow Plan Branch Locking

**Area:** parallel-execution

**Depends:** 0071

## Problem

V13 §31 requires narrow plan branch locking instead of holding the lock for the entire manager batch. With per-area concurrent managers, locking should be brief and targeted.

## Requirements

1. **Reading areas**: Brief lock to snapshot area content at start of tick. Done once for all areas, not per-manager. Lock acquired, area files read into memory, lock released.
2. **Agent execution**: No lock needed. Manager agents run in threads and produce ticket content in memory.
3. **Writing tickets**: Main thread acquires lock per completed manager, writes tickets for that manager, commits, releases. Each completed manager's write is a separate short lock acquisition.
4. **Architect**: Still holds lock for full duration (reads spec and writes area files). Acceptable because architect is sequential and runs before managers.
5. Ensure the existing `planWorktreeLock` (in `orchestrator.nim`) is used consistently for all plan branch access.
6. Verify that no agent threads touch the plan worktree directly — only the orchestrator main thread writes.
7. `make test` must pass.

## Notes

- The `planWorktreeLock` already exists in `src/scriptorium/orchestrator.nim`.
- This replaces the model where the lock was held for the entire manager batch execution.
- The lock management module is at `src/scriptorium/lock_management.nim`.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0072-narrow-plan-branch-locking

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Refactors lock acquisition boundaries in orchestrator.nim around existing planWorktreeLock — primarily restructuring when locks are acquired/released rather than adding new mechanisms, but concurrency locking changes carry moderate integration risk requiring careful testing.
