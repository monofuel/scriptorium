# Merge Queue Safety Contract Baseline

**Area:** merge-queue
**Status:** done

## Summary

The single-flight merge queue, quality gates, and ticket state transitions are fully implemented and tested.

## What Exists

- Single-flight: at most one pending item processed per pass.
- Queue processing flow in `orchestrator.nim`:
  1. Ensures queue metadata exists (`ensureMergeQueueInitialized()`).
  2. Sets `queue/merge/active.md` to the currently processed pending item.
  3. Merges `master` into the ticket branch worktree (`git merge --no-edit master`).
  4. Runs required quality targets in the ticket worktree: `make test`, then `make integration-test`.
  5. On success: fast-forward merges ticket branch into `master` (`git merge --ff-only`), appends merge success note, moves ticket `in-progress → done`.
  6. On failure: appends merge failure note, moves ticket `in-progress → open`.
- Queue metadata cleaned up after success, failure, or stale-item cleanup.
- Stale queue items (ticket already moved to `open` or `done`) removed with active metadata cleared.
- Merge success and failure notes include submit summary and relevant output tails.
- Stale managed worktrees for non-active tickets removable by cleanup.
- Legacy repo-local worktrees under `.scriptorium/worktrees` removable by cleanup and assignment flows.
- Tests: `integration_orchestrator_queue.nim`.
