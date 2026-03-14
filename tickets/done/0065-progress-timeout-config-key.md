# Add progressTimeout Config Key

**Area:** config-testing

Add the `agents.coding.progressTimeout` config key to `config.nim` as specified in V8, §34.

## Requirements

- Add `codingAgentProgressTimeoutMs*: int` to the `TimeoutConfig` object in `config.nim`.
- Default value: 600_000 (10 minutes in milliseconds, matching the spec default of 10 minutes).
- Load from `scriptorium.json` under a path that maps to `agents.coding.progressTimeout` (integer minutes in JSON, converted to milliseconds internally).
- Merge logic: if the parsed value is > 0, override the default.

## Implementation Notes

- The config key is defined in `config.nim` alongside existing timeout fields (`codingAgentHardTimeoutMs`, `codingAgentNoOutputTimeoutMs`, `codingAgentMaxAttempts`).
- The JSON field name should be `progressTimeout` nested under `agents.coding` or under `timeouts` — follow the existing pattern in `loadConfig`.
- Unit tests in `test_scriptorium.nim` should verify default value and JSON override.

## Acceptance Criteria

- `TimeoutConfig` has `codingAgentProgressTimeoutMs` field with 600_000 default.
- `loadConfig` reads and merges the value from `scriptorium.json`.
- Existing tests continue to pass.
- New unit test verifies default and override behavior.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0065-progress-timeout-config-key

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 10
- reasoning: Single config field addition following existing timeout patterns in config.nim, plus a straightforward unit test — one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0065-progress-timeout-config-key/.scriptorium/logs/0065/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0065-progress-timeout-config-key/.scriptorium/logs/0065/attempt-01.last_message.txt\n
### Agent Last Message
```text
All changes are committed. The implementation is complete:

- Added `codingAgentProgressTimeoutMs*: int` to `TimeoutConfig` in `config.nim`
- Default value: `600_000` (10 minutes in ms)
- Merge logic in `loadConfig`: overrides default when parsed value > 0
- Updated existing timeout tests to verify the default and custom override

The `submit_pr` MCP tool is not available in this environment. The commit is ready on branch `scriptorium/ticket-0065` for the orchestrator to pick up.
```

### Agent Stdout Tail
```text
rogressTimeoutMs*: int` to `TimeoutConfig` in `config.nim`\n- Default value: `600_000` (10 minutes in ms)\n- Merge logic in `loadConfig`: overrides default when parsed value > 0\n- Updated existing timeout tests to verify the default and custom override\n\nThe `submit_pr` MCP tool is not available in this environment. The commit is ready on branch `scriptorium/ticket-0065` for the orchestrator to pick up.","stop_reason":"end_turn","session_id":"a834a202-efbb-4d7b-9500-0d38c5865e73","total_cost_usd":0.41336324999999996,"usage":{"input_tokens":19,"cache_creation_input_tokens":18505,"cache_read_input_tokens":409174,"output_tokens":3721,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":18505,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":19,"outputTokens":3721,"cacheReadInputTokens":409174,"cacheCreationInputTokens":18505,"webSearchRequests":0,"costUSD":0.41336324999999996,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"8ab498a2-2352-4e36-8835-b96ef9556593"}
```

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0065-progress-timeout-config-key/.scriptorium/logs/0065/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0065-progress-timeout-config-key/.scriptorium/logs/0065/attempt-02.last_message.txt\n
### Agent Last Message
```text
`submit_pr` called successfully. The merge request has been enqueued for ticket 0065.

Summary of changes (already committed in `b881a43`):
- Added `codingAgentProgressTimeoutMs*: int` to `TimeoutConfig` in `config.nim`
- Set default value to `600_000` (10 minutes in milliseconds)
- Added merge logic in `loadConfig` following the existing pattern (override if > 0)
- Added unit test assertions for both default and custom override values
```

### Agent Stdout Tail
```text
ccessfully. The merge request has been enqueued for ticket 0065.\n\nSummary of changes (already committed in `b881a43`):\n- Added `codingAgentProgressTimeoutMs*: int` to `TimeoutConfig` in `config.nim`\n- Set default value to `600_000` (10 minutes in milliseconds)\n- Added merge logic in `loadConfig` following the existing pattern (override if > 0)\n- Added unit test assertions for both default and custom override values","stop_reason":"end_turn","session_id":"7ccdf377-95de-449a-a4e0-fcf442142ca2","total_cost_usd":0.84973875,"usage":{"input_tokens":43,"cache_creation_input_tokens":30281,"cache_read_input_tokens":1051935,"output_tokens":5372,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":30281,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":43,"outputTokens":5372,"cacheReadInputTokens":1051935,"cacheCreationInputTokens":30281,"webSearchRequests":0,"costUSD":0.84973875,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"dba44969-403f-411a-81b0-e965927c088a"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 2m31s

## Merge Queue Success
- Summary: Add codingAgentProgressTimeoutMs field to TimeoutConfig with 600_000 default, loadConfig merge logic, and unit tests for default and override behavior.\n
### Quality Check Output
```text
3-14T04:32:02Z] [INFO] session summary: avg_ticket_wall=0s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
[2026-03-14T04:32:02Z] [INFO] architect: generating areas from spec
[2026-03-14T04:32:03Z] [INFO] architect: areas updated
[2026-03-14T04:32:03Z] [INFO] manager: generating tickets
[2026-03-14T04:32:03Z] [INFO] merge queue: processing
[2026-03-14T04:32:03Z] [INFO] ticket 0001: review started (model=codex-fake-unit-test-model)
[2026-03-14T04:32:03Z] [WARN] ticket 0001: review agent stalled, defaulting to approve
[2026-03-14T04:32:03Z] [INFO] ticket 0001: merge started (make test running)
[2026-03-14T04:32:03Z] [INFO] ticket 0001: merge succeeded (test wall=0s)
[2026-03-14T04:32:03Z] [INFO] ticket 0001: in-progress -> done (total wall=31s, attempts=0)
[2026-03-14T04:32:03Z] [INFO] ticket 0001: post-analysis skipped (no prediction section)
[2026-03-14T04:32:03Z] [INFO] merge queue: item processed
[2026-03-14T04:32:03Z] [INFO] tick 0 summary: architect=updated manager=no-op coding=idle merge=processing open=0 in-progress=0 done=1
[2026-03-14T04:32:03Z] [INFO] session summary: uptime=1s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-14T04:32:03Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-10 global halt while red resumes after master health is restored
[2026-03-14T04:32:03Z] [WARN] master is unhealthy — skipping tick
[2026-03-14T04:32:33Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-14T04:32:33Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-11 integration-test failure on master blocks assignment of open tickets
--- tests/integration_review_agent_live.nim ---

[Suite] integration review agent live
  [OK] IT-REVIEW-01 real review agent calls submit_review with a real model
```

## Metrics
- wall_time_seconds: 1174
- coding_wall_seconds: 670
- test_wall_seconds: 338
- attempt_count: 2
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 632858

## Post-Analysis
- actual_difficulty: hard
- prediction_accuracy: underestimated
- brief_summary: Predicted easy, actual was hard with 2 attempt(s) in 19m34s.
