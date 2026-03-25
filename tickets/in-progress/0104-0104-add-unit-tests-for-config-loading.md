# 0104 Add unit tests for config loading

**Area:** config-testing
**Depends:** 0103

## Problem

There is no dedicated unit test file for the config module (`src/scriptorium/config.nim`). Config loading, default values, JSON merging, and environment variable overrides are untested in isolation.

## Requirements

Create `tests/test_config.nim` with the following test cases:

1. **Default config values** — Call `defaultConfig()` and verify all default values: agent models, harnesses, endpoints, concurrency (maxAgents=4, tokenBudgetMB=0), loop (enabled=false), discord (enabled=false, empty channelId, empty allowedUsers), log levels (empty strings).
2. **Missing config file** — Call `loadConfig()` with a temp directory that has no `scriptorium.json`. Verify it returns the default config.
3. **Partial JSON merge** — Write a minimal `scriptorium.json` (e.g. only `{"agents": {"coding": {"model": "custom-model"}}}`) to a temp dir, call `loadConfig()`, verify the specified field is overridden and all other fields retain defaults.
4. **Full JSON merge** — Write a `scriptorium.json` with all sections populated (agents, endpoints, concurrency, timeouts, loop, discord), call `loadConfig()`, verify all values are correctly loaded.
5. **Environment variable override for logLevel** — Set `SCRIPTORIUM_LOG_LEVEL` env var, write a config with a different `logLevel`, call `loadConfig()`, verify the env var wins. Clean up the env var after the test.
6. **Environment variable override for fileLogLevel** — Same as above for `SCRIPTORIUM_FILE_LOG_LEVEL`.
7. **Discord config loading** — Write a `scriptorium.json` with discord section, verify enabled, channelId, and allowedUsers are loaded correctly.
8. **discordTokenPresent** — Set/unset `DISCORD_TOKEN` env var and verify `discordTokenPresent()` returns the expected boolean.
9. **resolveModel with and without CLAUDE_CODE_USE_BEDROCK** — Verify model ID translation works.
10. **inferHarness** — Verify claude- prefix maps to claude-code, codex-/gpt- to codex, other to typoi.

Use `jsony` for writing test JSON files. Use `std/os` for temp directories and env vars. Use `std/tempfiles` or create temp dirs manually. Follow existing test patterns in the repo (e.g. `test_loop_system.nim`).

## Acceptance criteria

- `tests/test_config.nim` exists and covers all listed cases.
- `nim r tests/test_config.nim` passes.
- `make test` passes (the new file matches the `tests/test_*.nim` glob).
- No mocks or fakes — this tests the real `loadConfig` against temp files.

## Files to create

- `tests/test_config.nim`

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0104-0104-add-unit-tests-for-config-loading

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Single test file creation but requires reading and understanding the config module's API, writing 10 distinct test cases with temp file/env var management, and ensuring compilation — moderate complexity with possible iteration on import paths or API details.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0104/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0104/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Created `tests/test_config.nim` with all 10 required test cases, all passing. The test file covers:

1. Default config values
2. Missing config file returns defaults
3. Partial JSON merge (only specified field overridden)
4. Full JSON merge (all sections)
5. `SCRIPTORIUM_LOG_LEVEL` env var override
6. `SCRIPTORIUM_FILE_LOG_LEVEL` env var override
7. Discord config loading
8. `discordTokenPresent()` with/without `DISCORD_TOKEN`
9. `resolveModel` with/without `CLAUDE_CODE_USE_BEDROCK`
10. `inferHarness` prefix mapping
```

### Agent Stdout Tail
```text
alues\n2. Missing config file returns defaults\n3. Partial JSON merge (only specified field overridden)\n4. Full JSON merge (all sections)\n5. `SCRIPTORIUM_LOG_LEVEL` env var override\n6. `SCRIPTORIUM_FILE_LOG_LEVEL` env var override\n7. Discord config loading\n8. `discordTokenPresent()` with/without `DISCORD_TOKEN`\n9. `resolveModel` with/without `CLAUDE_CODE_USE_BEDROCK`\n10. `inferHarness` prefix mapping","stop_reason":"end_turn","session_id":"f7bbd7f2-b174-4193-a05a-0210c960fcb2","total_cost_usd":0.50799575,"usage":{"input_tokens":57,"cache_creation_input_tokens":35493,"cache_read_input_tokens":318859,"output_tokens":5058,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":35493},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":57,"outputTokens":5058,"cacheReadInputTokens":318859,"cacheCreationInputTokens":35493,"webSearchRequests":0,"costUSD":0.50799575,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"758c51e8-1bc2-4709-aabf-262bc248a9a6"}
```
