# Migrate Merge Queue Operations To Journal

**Area:** crash-recovery
**Depends:** 0066

Migrate merge queue operations to use the write-ahead journal for crash safety (V8, §32).

## Requirements

All merge queue operations must go through the journal protocol:

1. **Enqueue** (adding pending merge request in `merge_queue.nim`):
   - Journal steps: `write` new file under `queue/merge/pending/`.

2. **Dequeue / process** (moving from pending to active):
   - Journal steps: `write` `queue/merge/active.md` with merge item metadata, `remove` the pending file.

3. **Clear active** (after merge completes or fails):
   - Journal steps: `remove` `queue/merge/active.md`.

## Implementation Notes

- Use `beginJournalTransition`, `executeJournalSteps`, `completeJournalTransition` from journal infrastructure (ticket 0066).
- Replace direct file writes + git commits in `merge_queue.nim` with journal-based equivalents.
- Combine with ticket state transition when appropriate (e.g., merge success does both clear-active and move-to-done in one journal operation).

## Acceptance Criteria

- All merge queue operations (enqueue, dequeue, clear active) use the journal protocol.
- Journal file is created and cleaned up for each operation.
- Existing integration tests continue to pass.
- No `.scriptorium-journal.json` persists after clean operations.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0071-journal-merge-queue-operations
