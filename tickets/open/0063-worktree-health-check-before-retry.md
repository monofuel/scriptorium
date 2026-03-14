# Worktree Health Check Before Retry

**Area:** agent-execution

Implement worktree health validation before starting any retry attempt (stall, progress timeout, or crash) as specified in V8, §34.

## Requirements

Before each retry in `executeAssignedTicket` (in `coding_agent.nim`), validate the worktree:

1. **Corruption check:** Run `git status --porcelain` in the worktree. If it fails (non-zero exit), the worktree is corrupt.
   - Remove and recreate from ticket branch: `git worktree remove --force <path>` then `git worktree add <path> <branch>`.
   - Log: `ticket <id>: worktree corrupt, recreated from branch`.

2. **Uncommitted changes:** If `git status --porcelain` succeeds but has output, there are uncommitted changes.
   - Stage all and commit with message `scriptorium: save partial agent work (attempt <n>)` on the ticket branch.
   - Log: `ticket <id>: saved uncommitted agent work before retry`.

3. **Clean worktree:** If `git status --porcelain` succeeds with no output, proceed normally.

## Implementation Notes

- Insert the health check in the `while totalAttemptsUsed < maxAttempts` loop in `executeAssignedTicket`, just before the stall continuation prompt is built (around the `if isStall` block).
- Use existing `runCommandCapture` / `gitRun` / `gitCheck` helpers from `git_ops.nim`.
- The retry agent receives the worktree in a known-good state with all prior work committed.

## Acceptance Criteria

- Corrupt worktree is detected, removed, and recreated before retry.
- Uncommitted changes are committed before retry with the specified message format.
- Clean worktrees proceed without extra operations.
- Each case produces the specified log message.
- Unit tests cover all three cases (corrupt, dirty, clean).
