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

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0067-startup-recovery-sequence/.scriptorium/logs/0067/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0067-startup-recovery-sequence/.scriptorium/logs/0067/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Here's a summary of what was implemented:

**New file: `src/scriptorium/recovery.nim`** - Implements the `recoverFromCrash` procedure with 5 ordered steps:

1. **Clean Orphaned Worktrees** - Calls `cleanupStaleTicketWorktrees` and removes git worktree locks held by dead PIDs
2. **Detect Stale Agent Processes** - Scans ticket worktree directories for `.pid`/`.lock` files with dead PIDs
3. **Reconcile Dirty Plan Branch** - Delegates to `replayOrRollbackJournal` if journal exists, otherwise commits uncommitted changes
4. **Validate Merge Queue vs Master** - Uses `git merge-base --is-ancestor` to detect already-merged tickets and moves them to done
5. **Log Recovery Summary** - Single INFO line with counts, or "clean startup, no recovery needed"

**Modified: `src/scriptorium/orchestrator.nim`** - Added `recovery` import and `discard recoverFromCrash(repoPath)` call at the top of `runOrchestratorMainLoop`

**New file: `tests/test_recovery.nim`** - 12 unit tests covering each recovery step independently, including clean startup, dead PID cleanup, journal replay, and already-merged ticket completion.
```

### Agent Stdout Tail
```text
e: `tests/test_recovery.nim`** - 12 unit tests covering each recovery step independently, including clean startup, dead PID cleanup, journal replay, and already-merged ticket completion.","stop_reason":"end_turn","session_id":"9cd0ff10-3ae7-4b10-8003-e6f0d0042740","total_cost_usd":2.6278517500000005,"usage":{"input_tokens":44,"cache_creation_input_tokens":86270,"cache_read_input_tokens":3156246,"output_tokens":14046,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":86270,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":44,"outputTokens":14046,"cacheReadInputTokens":3156246,"cacheCreationInputTokens":86270,"webSearchRequests":0,"costUSD":2.4686805000000005,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":87,"outputTokens":8273,"cacheReadInputTokens":430755,"cacheCreationInputTokens":59715,"webSearchRequests":0,"costUSD":0.15917125,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"9e1ca099-f4ce-409e-afa9-2e70b617bc2b"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 2m53s
