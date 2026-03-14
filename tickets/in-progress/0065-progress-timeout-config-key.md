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
