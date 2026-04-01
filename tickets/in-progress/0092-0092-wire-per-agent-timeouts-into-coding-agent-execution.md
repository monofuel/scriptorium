# 0092 Wire per-agent timeouts into coding agent execution

**Area:** config-testing
**Priority:** medium
**Depends:** 0091

## Context

After ticket 0091 adds per-agent timeout fields to `AgentConfig`, the coding agent execution path needs to read timeouts from `config.agents.coding` instead of the global `config.timeouts` fields. This completes the per-agent timeout migration for the coding role.

## Task

1. In `src/scriptorium/agent_runner.nim` (and any other files that read `config.timeouts.codingAgentHardTimeoutMs`, `config.timeouts.codingAgentNoOutputTimeoutMs`, or `config.timeouts.codingAgentProgressTimeoutMs`), update references to read from `config.agents.coding.hardTimeout`, `config.agents.coding.noOutputTimeout`, and `config.agents.coding.progressTimeout` instead.
   - Use `grep` to find all references to `codingAgentHardTimeoutMs`, `codingAgentNoOutputTimeoutMs`, `codingAgentProgressTimeoutMs` across `src/`.
2. Keep `config.timeouts.codingAgentMaxAttempts` as-is — max attempts is not part of the per-agent timeout spec.
3. Update any tests in `tests/` that reference the global timeout fields to use the per-agent fields where appropriate.
4. Run `make test` and confirm all tests pass.

## Acceptance criteria

- Coding agent execution reads timeouts from `config.agents.coding.{hardTimeout, noOutputTimeout, progressTimeout}`.
- No remaining references to global `codingAgentHardTimeoutMs` / `codingAgentNoOutputTimeoutMs` / `codingAgentProgressTimeoutMs` in the execution path (config loading can keep them for backward compat).
- All unit tests pass.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0092-0092-wire-per-agent-timeouts-into-coding-agent-execution

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Straightforward find-and-replace of three timeout field references from global config to per-agent config paths, plus corresponding test updates, all within a single module with low integration risk.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0092/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0092/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. The changes:

- **`src/scriptorium/coding_agent.nim`**: Updated 3 timeout references from `cfg.timeouts.codingAgent{Hard,NoOutput,Progress}TimeoutMs` to `agentCfg.{hardTimeout,noOutputTimeout,progressTimeout}`, reading from the per-agent config.
- **`tests/test_config.nim`**: Added per-agent timeout values to the test JSON and assertions verifying they load correctly.

The global `config.timeouts` fields remain in config loading for backward compatibility, and `codingAgentMaxAttempts` is untouched as specified.
```

### Agent Stdout Tail
```text
 `cfg.timeouts.codingAgent{Hard,NoOutput,Progress}TimeoutMs` to `agentCfg.{hardTimeout,noOutputTimeout,progressTimeout}`, reading from the per-agent config.\n- **`tests/test_config.nim`**: Added per-agent timeout values to the test JSON and assertions verifying they load correctly.\n\nThe global `config.timeouts` fields remain in config loading for backward compatibility, and `codingAgentMaxAttempts` is untouched as specified.","stop_reason":"end_turn","session_id":"c5cfd5c2-9ed4-4db9-acd2-d442af5b589d","total_cost_usd":0.730826,"usage":{"input_tokens":33,"cache_creation_input_tokens":27212,"cache_read_input_tokens":868222,"output_tokens":5059,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":27212,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":33,"outputTokens":5059,"cacheReadInputTokens":868222,"cacheCreationInputTokens":27212,"webSearchRequests":0,"costUSD":0.730826,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"b7249b91-c16e-47de-a065-b7d7232429de"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 47s

**Review Reasoning:** , which is correct per the ticket. Let me verify the `agentCfg` variable is properly sourced from `config.agents.coding`.
Good. `agentCfg` is sourced from `cfg.agents.coding` (line 167), with an override path. The change correctly reads timeouts from the per-agent config. The test verifies the per-agent values load independently from the global values.

Let me also check that there's no issue with the `agentConfigOverride` path — if an override is provided, it should also carry timeout fields.
The implementation looks correct. The `agentConfigOverride` is a full `AgentConfig` object, so it would carry its own timeout fields if provided. Line 169 correctly keeps `codingAgentMaxAttempts` from the global config as specified in the ticket.

Now let me submit the review.


The diff is clean and correct. Let me summarize my findings:

1. **Ticket compliance**: All three timeout references in `coding_agent.nim` are updated from `cfg.timeouts.codingAgent{Hard,NoOutput,Progress}TimeoutMs` to `agentCfg.{hardTimeout,noOutputTimeout,progressTimeout}`. `codingAgentMaxAttempts` remains on the global config (line 169). No remaining global timeout references in the execution path.

2. **Convention compliance**: No new procs, imports, or variables introduced — just field reference changes. Naming follows camelCase. No style violations.

3. **Spec compliance**: The spec (section 9) lists `agents.coding.{hardTimeout, noOutputTimeout, progressTimeout}` as supported config keys. The implementation reads from exactly these fields.

4. **Test coverage**: The test adds per-agent timeout values (5000, 6000, 7000) distinct from the global values (1000, 2000, 3000), confirming they load independently. This is a good test design choice.

5. **Code quality**: No dead code, no unused imports, no leftover artifacts, no unrelated changes.
Review approved. The changes are minimal, correct, and well-tested — a straightforward field reference update that matches the ticket requirements exactly.
