# Add Concurrency Config Keys To scriptorium.json

**Area:** config-testing

## Problem

The `Config` type in `config.nim` does not include a `concurrency` field. The V5 spec (§24, §26) requires two new config keys:

- `concurrency.maxAgents` (integer, default 1) — maximum number of parallel coding agents.
- `concurrency.tokenBudgetMB` (optional integer megabytes) — cumulative session stdout byte budget.

These keys are listed in the config-testing area scope but are not yet implemented.

## Requirements

1. Add a `ConcurrencyConfig` object type with fields:
   - `maxAgents*: int` (default 1)
   - `tokenBudgetMB*: int` (default 0, meaning unlimited)
2. Add `concurrency*: ConcurrencyConfig` field to the `Config` type.
3. Initialize with defaults in `defaultConfig()` or equivalent.
4. Parse `concurrency.maxAgents` and `concurrency.tokenBudgetMB` from `scriptorium.json` in `loadConfig()`.
5. Add unit test in `tests/test_scriptorium.nim` verifying:
   - Default values when `concurrency` key is absent.
   - Correct parsing when both keys are present.
   - Correct parsing when only `maxAgents` is present.

## Acceptance Criteria

- `make test` passes with new tests.
- Config struct is available for use by parallel-execution implementation.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0045-concurrency-config-keys

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 15
- reasoning: Straightforward addition of a new config object type and field to an existing config struct, with default initialization, JSON parsing, and simple unit tests following established patterns.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0045-concurrency-config-keys/.scriptorium/logs/0045/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0045-concurrency-config-keys/.scriptorium/logs/0045/attempt-01.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` MCP tool doesn't appear to be available in the current environment. All changes are committed. Here's what was done:

**Changes:**

1. **`src/scriptorium/config.nim`** — Added `ConcurrencyConfig` object type with `maxAgents` (default 1) and `tokenBudgetMB` (default 0), added it as a field on `Config`, initialized defaults in `defaultConfig()`, and parsed both keys in `loadConfig()`.

2. **`tests/test_scriptorium.nim`** — Added 3 tests:
   - Default values when `concurrency` key is absent
   - Correct parsing when both keys are present
   - Correct parsing when only `maxAgents` is present

All tests pass via `make test`.
```

### Agent Stdout Tail
```text
e with `maxAgents` (default 1) and `tokenBudgetMB` (default 0), added it as a field on `Config`, initialized defaults in `defaultConfig()`, and parsed both keys in `loadConfig()`.\n\n2. **`tests/test_scriptorium.nim`** — Added 3 tests:\n   - Default values when `concurrency` key is absent\n   - Correct parsing when both keys are present\n   - Correct parsing when only `maxAgents` is present\n\nAll tests pass via `make test`.","stop_reason":"end_turn","session_id":"2686fc3a-1d42-4287-a480-b37a57ac046c","total_cost_usd":0.481107,"usage":{"input_tokens":20,"cache_creation_input_tokens":23290,"cache_read_input_tokens":490889,"output_tokens":3600,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":23290,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":20,"outputTokens":3600,"cacheReadInputTokens":490889,"cacheCreationInputTokens":23290,"webSearchRequests":0,"costUSD":0.481107,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"67d065b0-677d-47a0-9cf6-b1bc5965ddbb"}
```

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0045-concurrency-config-keys/.scriptorium/logs/0045/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0045-concurrency-config-keys/.scriptorium/logs/0045/attempt-02.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` MCP tool has been called successfully. The merge request is enqueued.

To summarize what was done (already implemented in a prior attempt):
- **`ConcurrencyConfig`** object type added to `config.nim` with `maxAgents` (default 1) and `tokenBudgetMB` (default 0)
- **`concurrency`** field added to the `Config` type
- Defaults initialized in `defaultConfig()`
- Parsing from `scriptorium.json` in `loadConfig()`
- Three unit tests added: default values when absent, both keys present, and maxAgents-only parsing
- All tests pass (`make test` exits 0)
```

### Agent Stdout Tail
```text
*`ConcurrencyConfig`** object type added to `config.nim` with `maxAgents` (default 1) and `tokenBudgetMB` (default 0)\n- **`concurrency`** field added to the `Config` type\n- Defaults initialized in `defaultConfig()`\n- Parsing from `scriptorium.json` in `loadConfig()`\n- Three unit tests added: default values when absent, both keys present, and maxAgents-only parsing\n- All tests pass (`make test` exits 0)","stop_reason":"end_turn","session_id":"b78ef347-6b9e-4da6-9ac9-cf5032b3d89c","total_cost_usd":0.5455040000000001,"usage":{"input_tokens":30,"cache_creation_input_tokens":22940,"cache_read_input_tokens":613958,"output_tokens":3800,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":22940,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":30,"outputTokens":3800,"cacheReadInputTokens":613958,"cacheCreationInputTokens":22940,"webSearchRequests":0,"costUSD":0.5455040000000001,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"cdb4a08f-8fd2-4162-9ac2-30b23f03706d"}
```

## Review
**Review:** approved
- Model: codex-fake-unit-test-model
- Backend: claude-code
- Exit Code: 1
- Wall Time: 7s
