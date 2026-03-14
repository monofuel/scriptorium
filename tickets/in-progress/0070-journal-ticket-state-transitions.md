# Migrate Ticket State Transitions To Journal

**Area:** crash-recovery
**Depends:** 0066

Migrate all ticket state transitions to use the write-ahead journal for crash safety (V8, §32).

## Requirements

All ticket state transitions must go through the journal protocol:

1. **open -> in-progress** (ticket assignment in `ticket_assignment.nim`):
   - Journal steps: `move` ticket file from `tickets/open/` to `tickets/in-progress/`, `write` updated content with worktree path.

2. **in-progress -> done** (merge success in `merge_queue.nim`):
   - Journal steps: `move` ticket file from `tickets/in-progress/` to `tickets/done/`, `write` updated content with metrics.

3. **in-progress -> open** (reopen on failure in `coding_agent.nim`):
   - Journal steps: `write` updated ticket content with run notes, `move` from `tickets/in-progress/` to `tickets/open/`.

## Implementation Notes

- Use `beginJournalTransition`, `executeJournalSteps`, `completeJournalTransition` from journal infrastructure (ticket 0066).
- Each transition is a single journal operation.
- Replace direct `moveFile` + `gitRun("add")` + `gitRun("commit")` sequences with journal-based equivalents.
- The journal adds two extra commits per transition (journal write and removal) — this is expected per V8 known limitations.

## Acceptance Criteria

- All three ticket state transitions use the journal protocol.
- Each transition creates and cleans up the journal file.
- Existing integration tests continue to pass.
- No `.scriptorium-journal.json` persists after clean operations.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0070-journal-ticket-state-transitions
