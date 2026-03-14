# Write-Ahead Journal Infrastructure

**Area:** crash-recovery

Implement the write-ahead journal file structure and protocol for atomic plan branch transitions (V8, §32).

## Requirements

### Journal File Structure
- Journal file: `.scriptorium-journal.json` in the plan worktree root.
- JSON structure with fields:
  - `operation`: string describing the transition (e.g., "ticket-assign", "merge-enqueue").
  - `timestamp`: ISO-8601 timestamp.
  - `steps`: array of step objects, each with `action` (`write`, `move`, `remove`) and relevant fields (`path`, `content`, `contentHash`, `source`, `destination`).
  - `commit_message`: the final commit message for the transition.

### Write-Ahead Protocol
1. Write the journal file describing all intended steps.
2. `git add` and commit the journal with `scriptorium: begin transition — <operation>`.
3. Execute filesystem operations (writes, moves, removes) as described in steps.
4. `git add -A` and commit with the transition's `commit_message`.
5. Remove the journal and commit with `scriptorium: complete transition`.

### Journal Replay/Rollback (for crash recovery)
- Read journal and inspect filesystem state for each step:
  - `write`: check file exists with expected content hash.
  - `move`: check destination exists, source does not.
  - `remove`: check file no longer exists.
- All steps applied: commit pending changes and remove journal (complete).
- Partial: replay remaining steps, commit, remove journal.
- None applied: roll back via `git checkout -- .`, remove journal, commit.
- Log: `recovery: rolled back incomplete transition` (or replayed/completed as appropriate).
- Replay/rollback must be deterministic — no human intervention required.

## Implementation Notes

- Create a new module `journal.nim` under `src/scriptorium/`.
- Export procs: `beginJournalTransition`, `executeJournalSteps`, `completeJournalTransition`, `replayOrRollbackJournal`, `journalExists`.
- Content hashes use SHA-1 (consistent with existing hash usage in the project).
- No journal file should persist across a clean orchestrator run.

## Acceptance Criteria

- Journal can be created, committed, executed, and cleaned up.
- Replay correctly handles: all-applied, partially-applied, and none-applied states.
- Rollback restores files to pre-transition state.
- Unit tests cover all three replay scenarios plus normal completion path.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0066-write-ahead-journal-infrastructure
