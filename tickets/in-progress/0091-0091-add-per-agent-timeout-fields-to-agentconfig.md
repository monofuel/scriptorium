# 0091 Add per-agent timeout fields to AgentConfig

**Area:** config-testing
**Priority:** medium

## Context

The area spec lists `agents.architect.{hardTimeout, noOutputTimeout, progressTimeout}` (and the same for coding, manager, reviewer) as supported config keys. Currently, timeouts are only defined globally under `TimeoutConfig` with coding-agent-specific field names. The config layer needs per-agent timeout fields so each role can have independent timeout settings.

## Task

1. In `src/scriptorium/config.nim`, add three new fields to the `AgentConfig` type:
   ```nim
   hardTimeout*: int
   noOutputTimeout*: int
   progressTimeout*: int
   ```
2. Update `defaultAgentConfig` to set default values for these fields. Use the same defaults currently in `TimeoutConfig`:
   - `hardTimeout: 14_400_000` (4 hours)
   - `noOutputTimeout: 300_000` (5 minutes)
   - `progressTimeout: 600_000` (10 minutes)
3. Update `mergeAgentConfig` to merge these fields when non-zero:
   ```nim
   if parsed.hardTimeout > 0:
     base.hardTimeout = parsed.hardTimeout
   if parsed.noOutputTimeout > 0:
     base.noOutputTimeout = parsed.noOutputTimeout
   if parsed.progressTimeout > 0:
     base.progressTimeout = parsed.progressTimeout
   ```
4. Do NOT remove the global `TimeoutConfig` or its loading — keep it for backward compatibility. The per-agent fields take precedence when set; consumers will be migrated in a follow-up ticket.
5. Add unit tests in `tests/test_config.nim`:
   - `testPerAgentTimeoutDefaults`: verify `defaultConfig().agents.coding.hardTimeout == 14_400_000`, same for other fields and roles.
   - `testPerAgentTimeoutOverride`: write a config JSON with `"agents": {"coding": {"hardTimeout": 5000}}`, load it, assert `cfg.agents.coding.hardTimeout == 5000` and other roles still have defaults.
   - `testPerAgentTimeoutFullOverride`: write a config JSON setting all three timeout fields on architect, verify all load correctly.
6. Register new test procs in the `when isMainModule` block.
7. Run `make test` and confirm all tests pass.

## Acceptance criteria

- `AgentConfig` has `hardTimeout`, `noOutputTimeout`, `progressTimeout` int fields.
- `mergeAgentConfig` merges non-zero parsed values into base.
- Default values match current global timeout defaults.
- Global `TimeoutConfig` is preserved (not removed).
- New unit tests pass.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0091-0091-add-per-agent-timeout-fields-to-agentconfig

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 11
- reasoning: Single-file type addition with three int fields, a merge helper update, and three straightforward unit tests — all in well-established patterns with no cross-module risk.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0091/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0091/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes submitted:

- **`src/scriptorium/config.nim`**: Added `hardTimeout`, `noOutputTimeout`, `progressTimeout` fields to `AgentConfig`. Set defaults in `defaultAgentConfig` (14.4M, 300K, 600K ms). Added non-zero merge logic in `mergeAgentConfig`. Global `TimeoutConfig` left untouched.
- **`tests/test_config.nim`**: Added `testPerAgentTimeoutDefaults`, `testPerAgentTimeoutOverride`, and `testPerAgentTimeoutFullOverride` — all passing.
```

### Agent Stdout Tail
```text
mitted:\n\n- **`src/scriptorium/config.nim`**: Added `hardTimeout`, `noOutputTimeout`, `progressTimeout` fields to `AgentConfig`. Set defaults in `defaultAgentConfig` (14.4M, 300K, 600K ms). Added non-zero merge logic in `mergeAgentConfig`. Global `TimeoutConfig` left untouched.\n- **`tests/test_config.nim`**: Added `testPerAgentTimeoutDefaults`, `testPerAgentTimeoutOverride`, and `testPerAgentTimeoutFullOverride` — all passing.","stop_reason":"end_turn","session_id":"21bf0a56-433c-400a-a0de-559053e95721","total_cost_usd":0.5443,"usage":{"input_tokens":20,"cache_creation_input_tokens":28952,"cache_read_input_tokens":537000,"output_tokens":3790,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":28952,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":20,"outputTokens":3790,"cacheReadInputTokens":537000,"cacheCreationInputTokens":28952,"webSearchRequests":0,"costUSD":0.5443,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"395df553-3f80-4f5e-99b2-4b739fa71f93"}
```
