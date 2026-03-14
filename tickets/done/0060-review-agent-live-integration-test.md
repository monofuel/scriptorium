# Review Agent Live Integration Test

**Area:** review-agent

## Problem

V7 §30 requires a live integration test for the review agent, similar to `integration_mcp_submit_pr_live.nim`. No integration test currently exists for the review agent flow.

## Requirements

### Live integration test
- Create `tests/integration_review_agent_live.nim`.
- Run the review agent with a real model (using the reviewer config from `scriptorium.json`).
- Provide a real diff against a real branch (not synthetic input).
- Start the MCP server so the review agent can call `submit_review`.
- Verify the review agent calls `submit_review` with either `approve` or `request_changes`.
- Verify the review decision is consumable via `consumeReviewDecision`.

### Test structure
- Follow patterns from `integration_mcp_submit_pr_live.nim`.
- Test requires API credentials and a running model.
- Test runs only in `make integration-test`, not `make test`.
- Test must clean up worktrees and branches after completion.

## Acceptance Criteria

- `tests/integration_review_agent_live.nim` exists and follows integration test conventions.
- Test runs a real review agent session with a real model and real diff.
- Test verifies `submit_review` was called.
- `make integration-test` includes the new test.
- No mocks or fakes used.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0060-review-agent-live-integration-test

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Single new test file but requires wiring together MCP server, review agent, real model, and git worktree cleanup — mitigated by having a clear template in integration_mcp_submit_pr_live.nim to follow, likely one attempt.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0060-review-agent-live-integration-test/.scriptorium/logs/0060/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0060-review-agent-live-integration-test/.scriptorium/logs/0060/attempt-01.last_message.txt\n
### Agent Last Message
```text
The PR has been submitted. The integration test has been created and committed, and `submit_pr` confirmed the merge request is enqueued.

**Summary of changes:**
- Created `tests/integration_review_agent_live.nim` with test `IT-REVIEW-01` that:
  - Starts a real MCP HTTP server with `submit_review` tool
  - Creates a temporary git repo with a real branch and diff (modifying `hello.nim`)
  - Builds a review agent prompt using `buildReviewAgentPrompt`
  - Runs the review agent via `runAgent` with a real model (configured via env vars or defaults)
  - Verifies `submit_review` was called with `approve` or `request_changes`
  - Verifies the decision is consumable via `consumeReviewDecision` and consumed only once
  - Cleans up temp directories after completion
  - Automatically included in `make integration-test` via the `integration_*.nim` glob pattern
```

### Agent Stdout Tail
```text
onsumable via `consumeReviewDecision` and consumed only once\n  - Cleans up temp directories after completion\n  - Automatically included in `make integration-test` via the `integration_*.nim` glob pattern","stop_reason":"end_turn","session_id":"bdaa8f94-3080-4b03-88ff-1f7224b03b16","total_cost_usd":1.3066264,"usage":{"input_tokens":37,"cache_creation_input_tokens":40477,"cache_read_input_tokens":1439233,"output_tokens":7513,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":40477,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":37,"outputTokens":7513,"cacheReadInputTokens":1439233,"cacheCreationInputTokens":40477,"webSearchRequests":0,"costUSD":1.16060775,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":73,"outputTokens":4183,"cacheReadInputTokens":383244,"cacheCreationInputTokens":69365,"webSearchRequests":0,"costUSD":0.14601865,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"7be139b0-230a-4673-a148-0a5662db8f93"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 1m42s

## Merge Queue Success
- Summary: Add live integration test for review agent flow. Creates tests/integration_review_agent_live.nim that starts a real MCP server, creates a test repo with a real diff, runs the review agent with a real model, and verifies submit_review is called and consumable via consumeReviewDecision.\n
### Quality Check Output
```text
3-14T01:27:14Z] [INFO] session summary: avg_ticket_wall=0s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
[2026-03-14T01:27:14Z] [INFO] architect: generating areas from spec
[2026-03-14T01:27:15Z] [INFO] architect: areas updated
[2026-03-14T01:27:15Z] [INFO] manager: generating tickets
[2026-03-14T01:27:15Z] [INFO] merge queue: processing
[2026-03-14T01:27:15Z] [INFO] ticket 0001: review started (model=codex-fake-unit-test-model)
[2026-03-14T01:27:16Z] [WARN] ticket 0001: review agent stalled, defaulting to approve
[2026-03-14T01:27:16Z] [INFO] ticket 0001: merge started (make test running)
[2026-03-14T01:27:16Z] [INFO] ticket 0001: merge succeeded (test wall=0s)
[2026-03-14T01:27:16Z] [INFO] ticket 0001: in-progress -> done (total wall=31s, attempts=0)
[2026-03-14T01:27:16Z] [INFO] ticket 0001: post-analysis skipped (no prediction section)
[2026-03-14T01:27:16Z] [INFO] merge queue: item processed
[2026-03-14T01:27:16Z] [INFO] tick 0 summary: architect=updated manager=no-op coding=idle merge=processing open=0 in-progress=0 done=1
[2026-03-14T01:27:16Z] [INFO] session summary: uptime=1s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-14T01:27:16Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-10 global halt while red resumes after master health is restored
[2026-03-14T01:27:16Z] [WARN] master is unhealthy — skipping tick
[2026-03-14T01:27:46Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-14T01:27:46Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-11 integration-test failure on master blocks assignment of open tickets
--- tests/integration_review_agent_live.nim ---

[Suite] integration review agent live
  [OK] IT-REVIEW-01 real review agent calls submit_review with a real model
```

## Metrics
- wall_time_seconds: 657
- coding_wall_seconds: 251
- test_wall_seconds: 286
- attempt_count: 1
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 434917

## Post-Analysis
- actual_difficulty: easy
- prediction_accuracy: overestimated
- brief_summary: Predicted medium, actual was easy with 1 attempt(s) in 10m57s.
