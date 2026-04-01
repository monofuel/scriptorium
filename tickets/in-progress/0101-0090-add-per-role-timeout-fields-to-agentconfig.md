# 0090 — Add per-role timeout fields to AgentConfig

**Area:** harness-backends
**Priority:** medium

## Problem

The spec (Section 9) requires each agent role to support `hardTimeout`, `noOutputTimeout`, and `progressTimeout` fields in `scriptorium.json` under `agents.<role>`. Currently `AgentConfig` in `src/scriptorium/config.nim` only has `harness`, `model`, and `reasoningEffort`. Timeouts are stored in a separate global `TimeoutConfig` object that is coding-agent-specific.

## Task

1. Add three new fields to the `AgentConfig` type in `src/scriptorium/config.nim`:
   - `hardTimeout*: int` (milliseconds, 0 = no timeout)
   - `noOutputTimeout*: int` (milliseconds, 0 = no timeout)
   - `progressTimeout*: int` (milliseconds, 0 = no timeout)

2. Update `defaultAgentConfig` to accept timeout defaults as parameters, or update `defaultConfig()` to set role-specific timeout defaults:
   - **architect**: noOutputTimeout 600000, hardTimeout 7200000, progressTimeout 0
   - **coding**: noOutputTimeout 300000, hardTimeout 14400000, progressTimeout 600000
   - **manager**: noOutputTimeout 300000, hardTimeout 3600000, progressTimeout 0
   - **reviewer**: noOutputTimeout 300000, hardTimeout 3600000, progressTimeout 0
   - **audit**: keep at 0 (unchanged behavior)

3. Update `mergeAgentConfig` to merge parsed timeout fields when they are > 0.

4. Add unit tests in `tests/test_config.nim` verifying:
   - Default config has the expected per-role timeout values.
   - Loading a `scriptorium.json` with per-role timeouts correctly overrides defaults.
   - Zero-value timeouts in JSON do not override non-zero defaults.

Use `jsony` for JSON parsing (already in use).

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0101-0090-add-per-role-timeout-fields-to-agentconfig

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Single-file type extension with default value wiring and a test file update; straightforward field additions to an existing config struct with no cross-module integration risk.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0101/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0101/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes submitted:

- **`src/scriptorium/config.nim`**: Added `hardTimeout`, `noOutputTimeout`, `progressTimeout` fields to `AgentConfig`. Updated `defaultAgentConfig` to accept timeout parameters. Set role-specific defaults in `defaultConfig()`. Extended `mergeAgentConfig` to merge timeout fields when > 0.
- **`tests/test_config.nim`**: Added timeout assertions to `testDefaultConfigValues`, plus two new tests: `testPerRoleTimeoutOverride` and `testZeroTimeoutDoesNotOverride`.
```

### Agent Stdout Tail
```text
**: Added `hardTimeout`, `noOutputTimeout`, `progressTimeout` fields to `AgentConfig`. Updated `defaultAgentConfig` to accept timeout parameters. Set role-specific defaults in `defaultConfig()`. Extended `mergeAgentConfig` to merge timeout fields when > 0.\n- **`tests/test_config.nim`**: Added timeout assertions to `testDefaultConfigValues`, plus two new tests: `testPerRoleTimeoutOverride` and `testZeroTimeoutDoesNotOverride`.","stop_reason":"end_turn","session_id":"c0a58e90-603d-4f22-9a60-c50f17592b69","total_cost_usd":0.943169,"usage":{"input_tokens":27,"cache_creation_input_tokens":47106,"cache_read_input_tokens":953393,"output_tokens":6877,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":47106,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":27,"outputTokens":6877,"cacheReadInputTokens":953393,"cacheCreationInputTokens":47106,"webSearchRequests":0,"costUSD":0.943169,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"8d13a4fe-62a4-4b1f-a474-550d13b565e4"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 21s

**Review Reasoning:** Let me review the changes carefully.
Now let me verify the `submit_review` tool is available.


The changes are clean and well-implemented. Let me verify against each check:

**Convention enforcement:** Fields use camelCase, proc has doc comment, no new imports needed, variable grouping is fine. All good.

**Spec compliance:** Section 9 lists `hardTimeout`, `noOutputTimeout`, `progressTimeout` per role. The defaults match the ticket spec (architect: 7.2M/600K/0, coding: 14.4M/300K/600K, manager: 3.6M/300K/0, reviewer: 3.6M/300K/0, audit: 0/0/0). `mergeAgentConfig` merges when > 0. All three required test cases are present.

**Code quality:** No dead code, no unused imports, no unrelated changes. The implementation is minimal and focused.
Review approved. The implementation is correct, minimal, and well-tested.
