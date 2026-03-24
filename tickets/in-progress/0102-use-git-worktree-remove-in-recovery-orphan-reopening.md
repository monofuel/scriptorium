# Use git worktree remove in recovery orphan reopening

**Area:** plan-state

## Problem

In `src/scriptorium/recovery.nim:274`, `reopenOrphanedInProgressTickets` removes stale worktree directories with `removeDir(worktreePath)` but does not call `git worktree remove --force` first. This leaves stale entries in `.git/worktrees/` that git continues to track.

The correct pattern is already used in `src/scriptorium/ticket_assignment.nim:323-325` (`cleanupStaleTicketWorktrees`), which calls `git worktree remove --force` first and then `removeDir()` as a fallback.

Recovery Step 1 (`cleanOrphanedWorktrees`) runs before Step 5 but cannot catch the worktrees that Step 5 later removes, so these stale entries persist until the next recovery or cleanup cycle.

## Fix

1. In `reopenOrphanedInProgressTickets` (`src/scriptorium/recovery.nim`), replace the bare `removeDir(worktreePath)` at line 275 with `gitCheck(repoPath, "worktree", "remove", "--force", worktreePath)` followed by `removeDir()` as a fallback (matching the pattern in `ticket_assignment.nim:323-325`). Note: `gitCheck` and the necessary git helper are already imported from `git_ops`.
2. Add a unit test in `tests/test_recovery.nim` that verifies reopening an orphaned ticket also properly removes the git worktree tracking entry (not just the directory).

## Files to modify

- `src/scriptorium/recovery.nim` — `reopenOrphanedInProgressTickets` worktree cleanup
- `tests/test_recovery.nim` — new test case

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0102-use-git-worktree-remove-in-recovery-orphan-reopening

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Single-file fix replacing removeDir with gitCheck+removeDir fallback pattern already established in the codebase, plus one new unit test in an existing test file.
