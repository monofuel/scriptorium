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

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Single-file refactor of merge_queue.nim replacing direct file writes with existing journal infrastructure (beginJournalTransition/executeJournalSteps/completeJournalTransition), three distinct operations to migrate but all follow the same pattern established by ticket 0066.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0071-journal-merge-queue-operations/.scriptorium/logs/0071/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0071-journal-merge-queue-operations/.scriptorium/logs/0071/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. All merge queue operations now use the write-ahead journal protocol:

1. **Enqueue** (`enqueueMergeRequest`): Uses journal to write the pending file
2. **Dequeue** (start of `processMergeQueue`): Uses journal to write `active.md` and remove the pending file
3. **Cleanup paths** (empty queue, terminal ticket): Use journal to clear `active.md`
4. Removed redundant `newRemoveStep(item.pendingPath)` from downstream transitions (done, reopen, park) since dequeue already handles it
5. Removed unused `clearActiveQueueInPlanPath` and `commitMergeQueueCleanup` procs

All 308 tests pass with 0 failures.
```

### Agent Stdout Tail
```text
ransitions (done, reopen, park) since dequeue already handles it\n5. Removed unused `clearActiveQueueInPlanPath` and `commitMergeQueueCleanup` procs\n\nAll 308 tests pass with 0 failures.","stop_reason":"end_turn","session_id":"d118e5b0-dafa-4930-ad81-5b9d8b612071","total_cost_usd":3.5930625999999988,"usage":{"input_tokens":78,"cache_creation_input_tokens":81121,"cache_read_input_tokens":4996029,"output_tokens":18794,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":81121,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":78,"outputTokens":18794,"cacheReadInputTokens":4996029,"cacheCreationInputTokens":81121,"webSearchRequests":0,"costUSD":3.475260749999999,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":52,"outputTokens":4779,"cacheReadInputTokens":308886,"cacheCreationInputTokens":50373,"webSearchRequests":0,"costUSD":0.11780185,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"fc7ff8df-d769-402d-bbc4-df7a1a184656"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 2m19s

## Merge Queue Success
- Summary: Migrate all merge queue operations (enqueue, dequeue, cleanup) to use the write-ahead journal protocol for crash safety. Removed redundant pending file removal from downstream transitions and unused helper procs.\n
### Quality Check Output
```text
s — dequeue 0001
[2026-03-14T07:01:22Z] [INFO] journal: transition complete
[2026-03-14T07:01:22Z] [INFO] ticket 0001: review started (model=codex-fake-unit-test-model)
[2026-03-14T07:01:22Z] [WARN] ticket 0001: review agent stalled, defaulting to approve
[2026-03-14T07:01:22Z] [INFO] ticket 0001: merge started (make test running)
[2026-03-14T07:01:22Z] [INFO] ticket 0001: merge succeeded (test wall=0s)
[2026-03-14T07:01:22Z] [INFO] ticket 0001: in-progress -> done (total wall=31s, attempts=0)
[2026-03-14T07:01:22Z] [INFO] ticket 0001: post-analysis skipped (no prediction section)
[2026-03-14T07:01:22Z] [INFO] journal: began transition — complete 0001
[2026-03-14T07:01:22Z] [INFO] journal: executed steps — complete 0001
[2026-03-14T07:01:22Z] [INFO] journal: transition complete
[2026-03-14T07:01:22Z] [INFO] merge queue: item processed
[2026-03-14T07:01:22Z] [INFO] tick 0 summary: architect=updated manager=no-op coding=idle merge=processing open=0 in-progress=0 done=1
[2026-03-14T07:01:22Z] [INFO] session summary: uptime=1s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-14T07:01:22Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-10 global halt while red resumes after master health is restored
[2026-03-14T07:01:23Z] [INFO] recovery: clean startup, no recovery needed
[2026-03-14T07:01:23Z] [WARN] master is unhealthy — skipping tick
[2026-03-14T07:01:53Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-14T07:01:53Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-11 integration-test failure on master blocks assignment of open tickets
--- tests/integration_review_agent_live.nim ---

[Suite] integration review agent live
  [OK] IT-REVIEW-01 real review agent calls submit_review with a real model
```

## Metrics
- wall_time_seconds: 1542
- coding_wall_seconds: 1129
- test_wall_seconds: 262
- attempt_count: 1
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 1056755

## Post-Analysis
- actual_difficulty: medium
- prediction_accuracy: accurate
- brief_summary: Predicted medium, actual was medium with 1 attempt(s) in 25m42s.
