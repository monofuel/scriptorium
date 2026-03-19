# Dynamic Default Branch Detection

**Area:** cli-init

## Problem

The codebase hardcodes `master` as the default branch in `git_ops.nim`,
`merge_queue.nim`, and `coding_agent.nim`. Projects using `main` or `develop`
as their default branch will break.

## Requirements

- Add a `resolveDefaultBranch()` proc that dynamically detects the default branch:
  1. Check `refs/remotes/origin/HEAD` first.
  2. If not set, probe for `master`, `main`, `develop` in that order.
  3. If nothing works, error with a clear message.
- During `scriptorium init`, after resolving, run
  `git remote set-head origin <branch>` to cache the result.
- Replace all hardcoded `master` references with calls to the resolver:
  - `git_ops.nim::masterHeadCommit()` — rename and use dynamic branch.
  - `merge_queue.nim` — any merge target references.
  - `coding_agent.nim` — any branch references.
- Add a unit test for the resolver with mocked git output.

## Files To Change

- `src/scriptorium/git_ops.nim` — add resolver, update `masterHeadCommit`.
- `src/scriptorium/merge_queue.nim` — replace hardcoded `master`.
- `src/scriptorium/coding_agent.nim` — replace hardcoded `master`.
- `src/scriptorium/init.nim` — call resolver and set-head during init.
- `tests/test_scriptorium.nim` or new test file — test the resolver.

## Acceptance Criteria

- No hardcoded `master` references remain in production code.
- Resolver correctly finds default branch from origin/HEAD or by probing.
- Init sets `origin/HEAD` after resolving.
- Clear error message when no default branch can be determined.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0055-default-branch-detection
