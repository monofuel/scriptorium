# Dynamic Default Branch Detection

**Area:** cli-init

## Problem

The codebase hardcodes `master` as the default branch in `git_ops.nim`,
`merge_queue.nim`, and `coding_agent.nim`. Projects using `main` or `develop`
as their default branch will break.

## Requirements

- Add a `resolveDefaultBranch()` proc that dynamically detects the default branch:
  1. Check `refs/remotes/origin/HEAD` first.
  2. If not set, probe for `master`, `main`, `develop` in that order.
  3. If nothing works, error with a clear message.
- During `scriptorium init`, after resolving, run
  `git remote set-head origin <branch>` to cache the result.
- Replace all hardcoded `master` references with calls to the resolver:
  - `git_ops.nim::masterHeadCommit()` — rename and use dynamic branch.
  - `merge_queue.nim` — any merge target references.
  - `coding_agent.nim` — any branch references.
- Add a unit test for the resolver with mocked git output.

## Files To Change

- `src/scriptorium/git_ops.nim` — add resolver, update `masterHeadCommit`.
- `src/scriptorium/merge_queue.nim` — replace hardcoded `master`.
- `src/scriptorium/coding_agent.nim` — replace hardcoded `master`.
- `src/scriptorium/init.nim` — call resolver and set-head during init.
- `tests/test_scriptorium.nim` or new test file — test the resolver.

## Acceptance Criteria

- No hardcoded `master` references remain in production code.
- Resolver correctly finds default branch from origin/HEAD or by probing.
- Init sets `origin/HEAD` after resolving.
- Clear error message when no default branch can be determined.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0055-default-branch-detection

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Multi-file search-and-replace of hardcoded branch refs plus a new resolver proc with straightforward fallback logic; moderate integration surface across 4-5 files but no deep architectural risk, one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0055-default-branch-detection/.scriptorium/logs/0055/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0055-default-branch-detection/.scriptorium/logs/0055/attempt-01.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` call succeeded — the orchestrator confirmed "Merge request enqueued." The ticket work is complete and queued for merge.
```

### Agent Stdout Tail
```text
ent":null},"parent_tool_use_id":null,"session_id":"4a8a4df4-c131-44b9-87af-0ec3e0c82b96","uuid":"c9e3387c-f125-40c8-8455-64090dd2ce79"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":22963,"duration_api_ms":517036,"num_turns":2,"result":"The `submit_pr` call succeeded — the orchestrator confirmed \"Merge request enqueued.\" The ticket work is complete and queued for merge.","stop_reason":"end_turn","session_id":"4a8a4df4-c131-44b9-87af-0ec3e0c82b96","total_cost_usd":3.830351749999999,"usage":{"input_tokens":4,"cache_creation_input_tokens":873,"cache_read_input_tokens":179175,"output_tokens":167,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":873},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":1402,"outputTokens":20574,"cacheReadInputTokens":5491496,"cacheCreationInputTokens":90119,"webSearchRequests":0,"costUSD":3.830351749999999,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"324a3e64-cad0-404e-8307-25c3e1dfb0b4"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 2m47s

## Merge Queue Success
- Summary: Add resolveDefaultBranch() that checks origin/HEAD then probes master/main/develop. Replace all hardcoded master references in git_ops, merge_queue, coding_agent, recovery, orchestrator. Cache resolved branch during init via git remote set-head. Add unit tests for the resolver.\n
### Quality Check Output
```text
-19T21:50:52Z] [WARN] ticket 0001: review agent stalled, defaulting to approve
[2026-03-19T21:50:52Z] [INFO] ticket 0001: merge started (make test running)
[2026-03-19T21:50:52Z] [INFO] ticket 0001: merge succeeded (test wall=0s)
[2026-03-19T21:50:52Z] [INFO] ticket 0001: in-progress -> done (total wall=31s, attempts=0)
[2026-03-19T21:50:52Z] [INFO] ticket 0001: post-analysis skipped (no prediction section)
[2026-03-19T21:50:52Z] [INFO] journal: began transition — complete 0001
[2026-03-19T21:50:52Z] [INFO] journal: executed steps — complete 0001
[2026-03-19T21:50:52Z] [INFO] journal: transition complete
[2026-03-19T21:50:52Z] [INFO] merge queue: item processed
[2026-03-19T21:50:52Z] [INFO] tick 0 summary: architect=updated manager=no-op coding=idle merge=processing open=0 in-progress=0 done=1
[2026-03-19T21:50:52Z] [INFO] session summary: uptime=1s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-19T21:50:52Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-10 global halt while red resumes after master health is restored
[2026-03-19T21:50:52Z] [INFO] recovery: clean startup, no recovery needed
[2026-03-19T21:50:52Z] [WARN] master is unhealthy — skipping tick
[2026-03-19T21:51:22Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-19T21:51:22Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
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
- wall_time_seconds: 2143
- coding_wall_seconds: 1684
- test_wall_seconds: 282
- attempt_count: 1
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 866829

## Post-Analysis
- actual_difficulty: medium
- prediction_accuracy: accurate
- brief_summary: Predicted medium, actual was medium with 1 attempt(s) in 35m43s.
