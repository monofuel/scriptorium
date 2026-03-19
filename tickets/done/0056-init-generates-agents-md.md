# Init Generates AGENTS.md From Template

**Area:** cli-init

## Problem

`scriptorium init` does not generate an AGENTS.md file. New projects have no
agent instructions until the user creates one manually.

## Requirements

- During init, check if `AGENTS.md` exists in the target repo root (on the
  default branch worktree, not the plan branch).
- If missing, copy `src/scriptorium/prompts/agents_example.md` to `AGENTS.md`.
- The template already exists as a staticRead resource in prompt_catalog.nim;
  use that or read the file directly.
- Commit the new AGENTS.md on the default branch (or leave it uncommitted for
  the user to review — follow what the spec says).
- Log which files were created.

## Files To Change

- `src/scriptorium/init.nim` — add AGENTS.md generation step.
- `tests/integration_cli.nim` — verify AGENTS.md is created when missing.

## Acceptance Criteria

- Running `scriptorium init` on a repo without AGENTS.md creates one from the template.
- Running `scriptorium init` on a repo that already has AGENTS.md skips this step.
- The generated file matches `agents_example.md` content.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0056-init-generates-agents-md

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Single-file change in init.nim to check for AGENTS.md existence and copy a template, plus a straightforward integration test addition — minimal logic complexity with one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0056-init-generates-agents-md/.scriptorium/logs/0056/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0056-init-generates-agents-md/.scriptorium/logs/0056/attempt-01.last_message.txt\n
### Agent Last Message
```text
The PR was successfully submitted — "Merge request enqueued." The work is complete.
```

### Agent Stdout Tail
```text
input_tokens":0},"output_tokens":1},"context_management":null},"parent_tool_use_id":null,"session_id":"4aefe7f5-478e-4d7e-b736-29b678bbd386","uuid":"3854991f-f68d-4714-8724-c87925953153"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":6364,"duration_api_ms":194362,"num_turns":2,"result":"The PR was successfully submitted — \"Merge request enqueued.\" The work is complete.","stop_reason":"end_turn","session_id":"4aefe7f5-478e-4d7e-b736-29b678bbd386","total_cost_usd":1.3344950000000004,"usage":{"input_tokens":4,"cache_creation_input_tokens":2322,"cache_read_input_tokens":85026,"output_tokens":156,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":2322},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":129,"outputTokens":7700,"cacheReadInputTokens":1190850,"cacheCreationInputTokens":87348,"webSearchRequests":0,"costUSD":1.3344950000000004,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"e273fb3a-3f03-4f15-862c-3ff2ed1be672"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 2m15s

## Merge Queue Success
- Summary: Add AGENTS.md generation during scriptorium init. When AGENTS.md is missing, copies agents_example.md template and commits it on the default branch. Skips if AGENTS.md already exists. Includes integration tests for both cases.\n
### Quality Check Output
```text
-19T22:11:19Z] [WARN] ticket 0001: review agent stalled, defaulting to approve
[2026-03-19T22:11:19Z] [INFO] ticket 0001: merge started (make test running)
[2026-03-19T22:11:19Z] [INFO] ticket 0001: merge succeeded (test wall=0s)
[2026-03-19T22:11:19Z] [INFO] ticket 0001: in-progress -> done (total wall=31s, attempts=0)
[2026-03-19T22:11:19Z] [INFO] ticket 0001: post-analysis skipped (no prediction section)
[2026-03-19T22:11:19Z] [INFO] journal: began transition — complete 0001
[2026-03-19T22:11:19Z] [INFO] journal: executed steps — complete 0001
[2026-03-19T22:11:19Z] [INFO] journal: transition complete
[2026-03-19T22:11:19Z] [INFO] merge queue: item processed
[2026-03-19T22:11:19Z] [INFO] tick 0 summary: architect=updated manager=no-op coding=idle merge=processing open=0 in-progress=0 done=1
[2026-03-19T22:11:20Z] [INFO] session summary: uptime=1s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-19T22:11:20Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-10 global halt while red resumes after master health is restored
[2026-03-19T22:11:20Z] [INFO] recovery: clean startup, no recovery needed
[2026-03-19T22:11:20Z] [WARN] master is unhealthy — skipping tick
[2026-03-19T22:11:50Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-19T22:11:50Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
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
- wall_time_seconds: 912
- coding_wall_seconds: 489
- test_wall_seconds: 281
- attempt_count: 1
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 192330

## Post-Analysis
- actual_difficulty: medium
- prediction_accuracy: underestimated
- brief_summary: Predicted easy, actual was medium with 1 attempt(s) in 15m12s.
