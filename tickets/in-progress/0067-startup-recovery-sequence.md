# Startup Recovery Sequence

**Area:** crash-recovery
**Depends:** 0066

Implement the `recoverFromCrash` procedure that runs before the first orchestrator tick (V8, §31).

## Requirements

On orchestrator start, before the first tick, execute these recovery steps in order:

### Step 1: Clean Orphaned Worktrees
- Call existing `cleanupStaleTicketWorktrees(repoPath)` to prune worktrees not corresponding to in-progress tickets.
- Additionally: remove git worktree locks held by dead PIDs. If a PID is alive but not a known scriptorium process, log warning and skip.
- Log each cleaned worktree: `recovery: cleaned orphaned worktree <path>`.

### Step 2: Detect Stale Agent Processes
- Scan `/tmp/scriptorium-*/` worktree directories for lock files or PID markers from previous agent processes.
- Dead PIDs: clean up and log `recovery: cleared stale agent marker for PID <pid>`.
- Live PIDs: log warning `recovery: stale agent process <pid> still running in <worktree>, manual intervention may be needed`.
- Do not kill orphaned agents automatically.

### Step 3: Reconcile Dirty Plan Branch
- Check plan worktree for uncommitted changes.
- If clean: skip.
- If journal file exists: delegate to `replayOrRollbackJournal` from journal infrastructure (ticket 0066).
- Otherwise: commit all uncommitted changes with `scriptorium: recovery commit (unclean shutdown)`.
- Log: `recovery: plan branch reconciled (<action>)` where action is `clean`, `journal-replayed`, `journal-rolled-back`, or `committed`.

### Step 4: Validate Merge Queue vs Master HEAD
- For each pending merge queue item, check if the ticket branch is already merged into `master` (via `git merge-base --is-ancestor`).
- If merged but ticket still in-progress: move ticket to done, remove queue entry, clear active marker.
- Commit: `scriptorium: recovery — completed already-merged ticket <id>`.

### Step 5: Log Recovery Summary
- Single INFO-level line: `recovery: cleaned <n> worktrees, cleared <m> stale markers, reconciled plan branch (<action>), completed <k> already-merged tickets`.
- If nothing needed: `recovery: clean startup, no recovery needed`.

## Implementation Notes

- Add `recoverFromCrash` proc in a new module or in `orchestrator.nim`.
- Call it at the top of `runOrchestrator` before entering the tick loop.
- Step 3 depends on journal infrastructure from ticket 0066.

## Acceptance Criteria

- Recovery runs automatically on orchestrator startup.
- Each step executes in the specified order.
- Log messages match the specified formats.
- Clean startup produces the "no recovery needed" message.
- Unit tests cover each recovery step independently.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0067-startup-recovery-sequence

## Prediction
- predicted_difficulty: hard
- predicted_duration_minutes: 30
- reasoning: Five-step recovery procedure touching worktree management, process scanning, git operations, journal replay integration, and merge queue reconciliation across multiple modules, with unit tests for each step — likely 2+ attempts due to integration complexity and dependency on ticket 0066's journal infrastructure.
