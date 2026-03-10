# Merge Queue Safety Contract

Covers the single-flight merge queue, quality gates, and ticket state transitions on merge.

## Scope

- Single-flight: at most one pending item processed per pass.
- Queue processing flow:
  1. Ensure queue metadata exists.
  2. Set `queue/merge/active.md` to the currently processed pending item.
  3. Merge `master` into the ticket branch worktree.
  4. Run required quality targets in the ticket worktree: `make test`, `make integration-test`.
  5. On success: fast-forward merge ticket branch into `master`, append merge success note, move ticket `in-progress -> done`.
  6. On failure: append merge failure note, move ticket `in-progress -> open`.
- Queue metadata cleaned up after success, failure, or stale-item cleanup.
- Stale queue items (ticket already moved to `open` or `done`) removed with active metadata cleared.
- Merge success and failure notes include submit summary and relevant output tails.
- Stale managed worktrees for non-active tickets removable by cleanup.
- Legacy repo-local worktrees under `.scriptorium/worktrees` removable by cleanup and assignment flows.

## Spec References

- Section 7: Merge Queue Safety Contract.
