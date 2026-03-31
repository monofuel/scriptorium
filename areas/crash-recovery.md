# Crash Recovery And Atomic Transitions

V8 feature: startup recovery sequence and write-ahead journal for atomic plan branch transitions.

## Scope

**Startup recovery sequence (§31):**
- On orchestrator start, before the first tick, run `recoverFromCrash` to detect and reconcile stale state.
- Recovery steps execute in order:
  1. **Clean orphaned worktrees:** call `cleanupStaleTicketWorktrees(repoPath)` to prune worktrees under `/tmp/scriptorium/` not corresponding to any in-progress ticket. Remove git worktree locks held by dead PIDs. If a PID is alive but not a known scriptorium process, log warning and skip. Log each cleaned worktree: `recovery: cleaned orphaned worktree <path>`.
  2. **Detect stale agent processes:** scan `/tmp/scriptorium-*/` worktree directories for lock files or PID markers from previous agent processes. Dead PIDs: clean up and log `recovery: cleared stale agent marker for PID <pid>`. Live PIDs: log warning `recovery: stale agent process <pid> still running in <worktree>, manual intervention may be needed`. Do not kill orphaned agents automatically.
  3. **Reconcile dirty plan branch:** check plan worktree for uncommitted changes. If clean, skip. If journal file exists, delegate to journal replay/rollback. Otherwise, commit all uncommitted changes with `scriptorium: recovery commit (unclean shutdown)`. Log: `recovery: plan branch reconciled (<action>)` where action is `clean`, `journal-replayed`, `journal-rolled-back`, or `committed`.
  4. **Validate merge queue vs default branch HEAD:** for each pending merge queue item, check if the ticket branch is already merged into the default branch (via `git merge-base --is-ancestor`). If merged but ticket still in-progress: move ticket to done, remove queue entry, clear active marker, commit `scriptorium: recovery — completed already-merged ticket <id>`. Clear stale active markers for tickets no longer in-progress.
  5. **Log recovery summary:** single INFO-level line: `recovery: cleaned <n> worktrees, cleared <m> stale markers, reconciled plan branch (<action>), completed <k> already-merged tickets`. If nothing needed: `recovery: clean startup, no recovery needed`.

**Atomic plan branch transitions (§32):**
- Multi-step plan branch operations wrapped in a write-ahead journal for crash safety.
- Journal file: `.scriptorium-journal.json` in the plan worktree root.
- Journal structure: JSON with `operation`, `timestamp`, `steps` array (each step has `action`: `write`/`move`/`remove` with relevant fields), and `commit_message`.
- Write-ahead protocol:
  1. Write the journal file describing all intended steps.
  2. `git add` and commit the journal with `scriptorium: begin transition — <operation>`.
  3. Execute filesystem operations (writes, moves, removes) as described.
  4. `git add -A` and commit with the transition's commit message.
  5. Remove the journal and commit with `scriptorium: complete transition`.
- Crash recovery replay (used by startup step 3):
  - Read journal and inspect filesystem state for each step.
  - `write`: check file exists with expected content hash. `move`: check destination exists, source does not. `remove`: check file no longer exists.
  - All steps applied: commit and remove journal (complete).
  - Partial: replay remaining steps, commit, remove journal.
  - None applied: roll back via `git checkout -- .`, remove journal, commit. Log: `recovery: rolled back incomplete transition`.
  - Replay/rollback is deterministic — no human intervention required.
- All ticket state transitions (open->in-progress, in-progress->done, in-progress->open) must use the journal.
- Merge queue operations (enqueue, dequeue, clear active) must use the journal.
- No journal file persists across a clean orchestrator run.

## V8 Known Limitations

- Orchestrator does not automatically kill orphaned agent processes — operators handle this manually.
- Write-ahead journal adds two extra commits per transition (journal write and removal), increasing plan branch commit volume.

## Spec References

- Section 31: Startup Recovery Sequence (V8).
- Section 32: Atomic Plan Branch Transitions (V8).
