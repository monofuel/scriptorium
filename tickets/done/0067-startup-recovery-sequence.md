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

## Merge Queue Success
- Summary: Add startup recovery sequence (recoverFromCrash) that runs before the first orchestrator tick. Implements 5 ordered steps: clean orphaned worktrees, detect stale agent processes, reconcile dirty plan branch with journal replay/rollback, validate merge queue vs master HEAD, and log recovery summary. Includes unit tests for each step.\n
### Quality Check Output
```text
FO] recovery: clean startup, no recovery needed
[2026-03-14T05:23:41Z] [INFO] architect: generating areas from spec
[2026-03-14T05:23:42Z] [INFO] architect: areas updated
[2026-03-14T05:23:42Z] [INFO] manager: generating tickets
[2026-03-14T05:23:42Z] [INFO] merge queue: processing
[2026-03-14T05:23:42Z] [INFO] ticket 0001: review started (model=codex-fake-unit-test-model)
[2026-03-14T05:23:43Z] [WARN] ticket 0001: review agent stalled, defaulting to approve
[2026-03-14T05:23:43Z] [INFO] ticket 0001: merge started (make test running)
[2026-03-14T05:23:43Z] [INFO] ticket 0001: merge succeeded (test wall=0s)
[2026-03-14T05:23:43Z] [INFO] ticket 0001: in-progress -> done (total wall=31s, attempts=0)
[2026-03-14T05:23:43Z] [INFO] ticket 0001: post-analysis skipped (no prediction section)
[2026-03-14T05:23:43Z] [INFO] merge queue: item processed
[2026-03-14T05:23:43Z] [INFO] tick 0 summary: architect=updated manager=no-op coding=idle merge=processing open=0 in-progress=0 done=1
[2026-03-14T05:23:43Z] [INFO] session summary: uptime=1s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-14T05:23:43Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-10 global halt while red resumes after master health is restored
[2026-03-14T05:23:43Z] [INFO] recovery: clean startup, no recovery needed
[2026-03-14T05:23:43Z] [WARN] master is unhealthy — skipping tick
[2026-03-14T05:24:13Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-14T05:24:13Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-11 integration-test failure on master blocks assignment of open tickets
--- tests/integration_review_agent_live.nim ---

[Suite] integration review agent live
  [OK] IT-REVIEW-01 real review agent calls submit_review with a real model
```

## Metrics
- wall_time_seconds: 1315
- coding_wall_seconds: 860
- test_wall_seconds: 268
- attempt_count: 1
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 716708

## Post-Analysis
- actual_difficulty: medium
- prediction_accuracy: overestimated
- brief_summary: Predicted hard, actual was medium with 1 attempt(s) in 21m55s.
