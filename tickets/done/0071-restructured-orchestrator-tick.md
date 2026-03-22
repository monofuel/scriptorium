# Restructured Orchestrator Tick For Interleaved Manager/Coder Execution

**Area:** parallel-execution

**Depends:** 0069

## Problem

V13 §30 requires a restructured tick where managers and coders are interleaved rather than strictly sequential. The current tick runs architect → manager (blocking batch) → coding → merge. The new tick must poll completions first, then start both managers and coders based on available slots.

## Requirements

Refactor the tick loop in `orchestrator.nim` to follow this order:

1. **Poll completed agents** (managers + coders) via `checkCompletedAgents()`.
   - For completed managers: acquire plan lock, write tickets via `writeTicketsForArea()`, commit, release. Log results.
   - For completed coders: handle as before (move ticket, queue merge, etc).
2. **Check backoff / health**: Rate limit backoff, master health check.
3. **Run architect** (sequential, if spec changed). Must complete before managers are spawned.
4. **Read areas needing tickets** (brief plan lock to snapshot area content).
5. **For each area needing tickets**, if slots available in the shared pool, start a manager agent.
6. **For each assignable ticket**, if slots available, start a coding agent.
7. **Process at most one merge-queue item**.
8. **Sleep**.

Additional requirements:
- Managers prioritized over coders when slots are scarce (step 5 runs before step 6).
- If a manager finishes and produces tickets while another manager is running, those tickets can be assigned to coding agents on the next tick.
- When `maxAgents` is 1, behavior collapses to sequential execution as before.
- Remove the serial-mode special path if it can be unified with the parallel path.
- `make test` must pass. Update existing orchestrator tests to match new tick structure.

## Notes

- This ticket restructures the orchestrator tick loop in `src/scriptorium/orchestrator.nim`.
- Depends on the shared agent pool (0068) and per-area concurrent managers (0069) being in place.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0071-restructured-orchestrator-tick

## Prediction
- predicted_difficulty: hard
- predicted_duration_minutes: 32
- reasoning: Major refactor of the orchestrator tick loop touching core control flow in orchestrator.nim, requiring reordering of manager/coder interleaving logic, unifying serial/parallel paths, and updating existing orchestrator tests — high integration risk with concurrency semantics likely requiring 2+ attempts.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0071-restructured-orchestrator-tick/.scriptorium/logs/0071/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0071-restructured-orchestrator-tick/.scriptorium/logs/0071/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Here's a summary of the changes:

**File changed:** `src/scriptorium/orchestrator.nim` (85 insertions, 69 deletions)

**Key restructuring:**
1. **Step 1 — Poll completions**: Removed the `maxAgents > 1` guard so `checkCompletedAgents()` runs every tick (no-op in serial mode)
2. **Step 2 — Backoff/health**: Unchanged
3. **Step 3 — Architect**: Unchanged (sequential, gated on `hasRunnableSpec`)
4. **Step 4+5 — Managers**: Replaced `launchManagerAreasAsync(repoPath, maxAgents)` with inline logic that checks `emptySlotCount()` before each launch, giving managers slot priority over coders
5. **Step 6 — Coders**: Moved outside the `hasRunnableSpec` block (still effectively gated by ticket availability). Managers fill slots first, coders get remaining slots
6. **Step 7 — Merge queue**: Same, also moved outside `hasRunnableSpec` gate
7. **Shutdown**: Simplified `runningAgentCount() > 0` check (removed redundant `maxAgents > 1` guard)
```

### Agent Stdout Tail
```text
 also moved outside `hasRunnableSpec` gate\n7. **Shutdown**: Simplified `runningAgentCount() > 0` check (removed redundant `maxAgents > 1` guard)","stop_reason":"end_turn","session_id":"37829c50-bd6b-4255-8a9c-e36b77008fc3","total_cost_usd":2.0100010999999998,"usage":{"input_tokens":1938,"cache_creation_input_tokens":83335,"cache_read_input_tokens":1549302,"output_tokens":23342,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":83335},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":1938,"outputTokens":23342,"cacheReadInputTokens":1549302,"cacheCreationInputTokens":83335,"webSearchRequests":0,"costUSD":1.8887347499999998,"contextWindow":200000,"maxOutputTokens":64000},"us.anthropic.claude-haiku-4-5-20251001-v1:0":{"inputTokens":14340,"outputTokens":4773,"cacheReadInputTokens":117826,"cacheCreationInputTokens":57023,"webSearchRequests":0,"costUSD":0.12126635,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"0b24904a-5018-4ff7-85ea-dad0f6b626a0"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 1m16s

## Merge Queue Success
- Summary: Restructured orchestrator tick loop for interleaved manager/coder execution. Completion polling now runs unconditionally, managers check slot availability before launching (prioritized over coders), and coding/merge steps are structurally separated from the hasRunnableSpec gate. All existing tests pass.\n
### Quality Check Output
```text
Z] [INFO] ticket 0001: merge succeeded (test wall=0s)
[2026-03-22T07:13:15Z] [INFO] ticket 0001: in-progress -> done (total wall=1m34s, attempts=0)
[2026-03-22T07:13:15Z] [INFO] ticket 0001: post-analysis skipped (no prediction section)
[2026-03-22T07:13:15Z] [INFO] journal: began transition — complete 0001
[2026-03-22T07:13:15Z] [INFO] journal: executed steps — complete 0001
[2026-03-22T07:13:15Z] [INFO] journal: transition complete
[2026-03-22T07:13:15Z] [INFO] merge queue: item processed
[2026-03-22T07:13:15Z] [INFO] tick 0 summary: architect=updated manager=no-op coding=1/4 agents merge=processing open=0 in-progress=0 done=1
[2026-03-22T07:13:15Z] [INFO] shutdown: waiting for 1 running agent(s)
[2026-03-22T07:20:36Z] [INFO] session summary: uptime=8m25s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-22T07:20:36Z] [INFO] session summary: avg_ticket_wall=31s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-10 global halt while red resumes after master health is restored
[2026-03-22T07:20:36Z] [INFO] recovery: clean startup, no recovery needed
[2026-03-22T07:20:36Z] [INFO] agent slots: 0/4 (manager queue-processing finished, 0 tickets)
[2026-03-22T07:20:36Z] [WARN] master is unhealthy — skipping tick
[2026-03-22T07:21:06Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-22T07:21:06Z] [INFO] session summary: avg_ticket_wall=31s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-11 integration-test failure on master blocks assignment of open tickets
--- tests/integration_review_agent_live.nim ---

[Suite] integration review agent live
  [OK] IT-REVIEW-01 real review agent calls submit_review with a real model
--- tests/integration_typoi_harness.nim ---

[Suite] integration typoi harness
  [SKIPPED] real typoi one-shot smoke test
  [SKIPPED] real typoi MCP tool call against live server
```

## Metrics
- wall_time_seconds: 2022
- coding_wall_seconds: 1113
- test_wall_seconds: 825
- attempt_count: 1
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 660180

## Post-Analysis
- actual_difficulty: medium
- prediction_accuracy: overestimated
- brief_summary: Predicted hard, actual was medium with 1 attempt(s) in 33m42s.
