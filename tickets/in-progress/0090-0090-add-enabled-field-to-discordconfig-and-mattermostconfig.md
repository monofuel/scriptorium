# 0090 Add `enabled` field to DiscordConfig and MattermostConfig

**Area:** config-testing
**Priority:** medium

## Context

The area spec requires `discord.{enabled, serverId, channelId, allowedUserIds}` and `mattermost.{enabled, url, channelId, allowedUserIds}`. Both `DiscordConfig` and `MattermostConfig` in `src/scriptorium/config.nim` are currently missing the `enabled: bool` field. The spec (V12) lists `enabled` as a supported config key for both sections.

## Task

1. Add `enabled*: bool` to the `DiscordConfig` type in `src/scriptorium/config.nim`.
2. Add `enabled*: bool` to the `MattermostConfig` type in `src/scriptorium/config.nim`.
3. In `defaultConfig()`, set both `discord.enabled` and `mattermost.enabled` to `false` (they are already defaulting to false implicitly, but make it explicit in the constructor).
4. In `loadConfig()`, inside the `if raw.contains("\"discord\"")` block, merge the `enabled` field: `result.discord.enabled = parsed.discord.enabled`.
5. Do the same for the mattermost block: `result.mattermost.enabled = parsed.mattermost.enabled`.
6. Add unit tests in `tests/test_config.nim`:
   - `testDiscordEnabledField`: write a config JSON with `"discord": {"enabled": true, "serverId": "s1"}`, load it, assert `cfg.discord.enabled == true`.
   - `testMattermostEnabledField`: write a config JSON with `"mattermost": {"enabled": true, "url": "https://mm.example.com"}`, load it, assert `cfg.mattermost.enabled == true`.
   - Verify that when `enabled` is not set, it defaults to `false`.
7. Register the new test procs in the `when isMainModule` block.
8. Run `make test` and confirm all tests pass.

## Acceptance criteria

- `DiscordConfig` and `MattermostConfig` types both have an `enabled*: bool` field.
- `loadConfig` correctly reads `enabled` from JSON for both sections.
- Default value is `false` for both.
- New unit tests pass.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0090-0090-add-enabled-field-to-discordconfig-and-mattermostconfig

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 10
- reasoning: Single-file type addition with explicit field merging in config loader, plus straightforward unit tests in one test file — minimal logic complexity, one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0090/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0090/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes submitted:

- Added `enabled*: bool` to `DiscordConfig` and `MattermostConfig` types
- Set explicit `enabled: false` defaults in `defaultConfig()`
- Added `enabled` field merging in `loadConfig()` for both discord and mattermost blocks
- Added `testDiscordEnabledField` and `testMattermostEnabledField` unit tests (including default-false verification)
- Updated `testDefaultConfigValues` to assert both enabled defaults
- All tests pass
```

### Agent Stdout Tail
```text
ool` to `DiscordConfig` and `MattermostConfig` types\n- Set explicit `enabled: false` defaults in `defaultConfig()`\n- Added `enabled` field merging in `loadConfig()` for both discord and mattermost blocks\n- Added `testDiscordEnabledField` and `testMattermostEnabledField` unit tests (including default-false verification)\n- Updated `testDefaultConfigValues` to assert both enabled defaults\n- All tests pass","stop_reason":"end_turn","session_id":"348eab94-8939-4fb4-809a-9f9d5c0386cc","total_cost_usd":0.5034782499999999,"usage":{"input_tokens":17,"cache_creation_input_tokens":30533,"cache_read_input_tokens":416124,"output_tokens":4180,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":30533,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":17,"outputTokens":4180,"cacheReadInputTokens":416124,"cacheCreationInputTokens":30533,"webSearchRequests":0,"costUSD":0.5034782499999999,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"6959c019-515f-4ee2-a97c-0dce89cd35bc"}
```
