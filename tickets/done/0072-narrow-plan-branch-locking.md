# Narrow Plan Branch Locking

**Area:** parallel-execution

**Depends:** 0071

## Problem

V13 §31 requires narrow plan branch locking instead of holding the lock for the entire manager batch. With per-area concurrent managers, locking should be brief and targeted.

## Requirements

1. **Reading areas**: Brief lock to snapshot area content at start of tick. Done once for all areas, not per-manager. Lock acquired, area files read into memory, lock released.
2. **Agent execution**: No lock needed. Manager agents run in threads and produce ticket content in memory.
3. **Writing tickets**: Main thread acquires lock per completed manager, writes tickets for that manager, commits, releases. Each completed manager's write is a separate short lock acquisition.
4. **Architect**: Still holds lock for full duration (reads spec and writes area files). Acceptable because architect is sequential and runs before managers.
5. Ensure the existing `planWorktreeLock` (in `orchestrator.nim`) is used consistently for all plan branch access.
6. Verify that no agent threads touch the plan worktree directly — only the orchestrator main thread writes.
7. `make test` must pass.

## Notes

- The `planWorktreeLock` already exists in `src/scriptorium/orchestrator.nim`.
- This replaces the model where the lock was held for the entire manager batch execution.
- The lock management module is at `src/scriptorium/lock_management.nim`.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0072-narrow-plan-branch-locking

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Refactors lock acquisition boundaries in orchestrator.nim around existing planWorktreeLock — primarily restructuring when locks are acquired/released rather than adding new mechanisms, but concurrency locking changes carry moderate integration risk requiring careful testing.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0072-narrow-plan-branch-locking/.scriptorium/logs/0072/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0072-narrow-plan-branch-locking/.scriptorium/logs/0072/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Here's a summary of the changes:

**5 files changed:**

1. **`src/scriptorium/manager_agent.nim`** — `executeManagerForArea` now uses `repoPath` as working directory (not `planPath`), removed plan worktree fallback. `runManagerForAreas` restructured for narrow locking: brief lock to snapshot areas → no lock during agent execution → brief lock per completed manager to write tickets.

2. **`src/scriptorium/prompt_builders.nim`** — Removed `planPath` parameter from `buildManagerTicketsPrompt`.

3. **`src/scriptorium/prompts/manager_tickets.md`** — Updated prompt to instruct agents to output tickets as fenced markdown blocks instead of writing files to the plan worktree.

4. **`tests/test_manager_agent.nim`** — Updated test calls to match new `buildManagerTicketsPrompt` signature.

5. **`tests/test_prompt_catalog.nim`** — Removed check for `WORKTREE_PATH` in manager template.
```

### Agent Stdout Tail
```text
mpt`.\n\n3. **`src/scriptorium/prompts/manager_tickets.md`** — Updated prompt to instruct agents to output tickets as fenced markdown blocks instead of writing files to the plan worktree.\n\n4. **`tests/test_manager_agent.nim`** — Updated test calls to match new `buildManagerTicketsPrompt` signature.\n\n5. **`tests/test_prompt_catalog.nim`** — Removed check for `WORKTREE_PATH` in manager template.","stop_reason":"end_turn","session_id":"2e20f3f9-762d-44f4-b346-55933f59a757","total_cost_usd":2.032117,"usage":{"input_tokens":9669,"cache_creation_input_tokens":77306,"cache_read_input_tokens":2244269,"output_tokens":15139,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":77306},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":9669,"outputTokens":15139,"cacheReadInputTokens":2244269,"cacheCreationInputTokens":77306,"webSearchRequests":0,"costUSD":2.032117,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"b0c40528-8c61-4fe0-b2b0-61d960d38539"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 1m38s

## Merge Queue Success
- Summary: Narrow plan branch locking for manager execution: restructured lock acquisition so areas are read with a brief lock, managers execute without holding the lock, and tickets are written with brief per-manager locks. Manager agents no longer touch the plan worktree directly — they run in the project repo and produce tickets via stdout.\n
### Quality Check Output
```text
Z] [INFO] ticket 0001: merge succeeded (test wall=0s)
[2026-03-22T07:46:40Z] [INFO] ticket 0001: in-progress -> done (total wall=1m34s, attempts=0)
[2026-03-22T07:46:40Z] [INFO] ticket 0001: post-analysis skipped (no prediction section)
[2026-03-22T07:46:40Z] [INFO] journal: began transition — complete 0001
[2026-03-22T07:46:40Z] [INFO] journal: executed steps — complete 0001
[2026-03-22T07:46:40Z] [INFO] journal: transition complete
[2026-03-22T07:46:40Z] [INFO] merge queue: item processed
[2026-03-22T07:46:40Z] [INFO] tick 0 summary: architect=updated manager=no-op coding=1/4 agents merge=processing open=0 in-progress=0 done=1
[2026-03-22T07:46:41Z] [INFO] shutdown: waiting for 1 running agent(s)
[2026-03-22T07:47:12Z] [INFO] session summary: uptime=1m35s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-22T07:47:12Z] [INFO] session summary: avg_ticket_wall=31s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-10 global halt while red resumes after master health is restored
[2026-03-22T07:47:12Z] [INFO] recovery: clean startup, no recovery needed
[2026-03-22T07:47:12Z] [INFO] agent slots: 0/4 (manager queue-processing finished, 4 tickets)
[2026-03-22T07:47:12Z] [WARN] master is unhealthy — skipping tick
[2026-03-22T07:47:42Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-22T07:47:42Z] [INFO] session summary: avg_ticket_wall=31s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
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
- wall_time_seconds: 952
- coding_wall_seconds: 429
- test_wall_seconds: 410
- attempt_count: 1
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 511407

## Post-Analysis
- actual_difficulty: medium
- prediction_accuracy: accurate
- brief_summary: Predicted medium, actual was medium with 1 attempt(s) in 15m52s.
