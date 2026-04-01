# 0090 Use dynamic default branch name in health cache log messages

**Area:** health-cache
**Priority:** medium

## Summary

The `isMasterHealthy` proc in `src/scriptorium/orchestrator.nim` hardcodes "master" in its log messages (e.g., `master health: cached healthy for ...`, `master is unhealthy — skipping tick`). The spec requires these messages to use the actual resolved default branch name (which may be `main`, `develop`, etc.).

## Acceptance criteria

- Call `resolveDefaultBranch(repoPath)` (from `git_ops`) once at the start of `isMasterHealthy` and use the result in all log messages.
- The log lines in `isMasterHealthy` should read e.g. `main health: cached healthy for <hash>` when the default branch is `main`.
- Also update the log lines at orchestrator.nim lines 232 and 235 that say "master is unhealthy" / "master is healthy again" to use the dynamic branch name.
- Update the debug log at line 226 (`checking master health`) similarly.
- Do not rename the proc or the `MasterHealthState` type — only change the string literals in log calls.

## Files to modify

- `src/scriptorium/orchestrator.nim`

## Notes

- `resolveDefaultBranch` is already imported via `git_ops`. Use `&` format strings per project convention.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0094-0090-use-dynamic-default-branch-name-in-health-cache-log-messages
