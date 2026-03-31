# 0075 Add MattermostConfig to config.nim

**Area:** chat-bots

## Description

Add Mattermost configuration support to `src/scriptorium/config.nim` so the Mattermost bot can be configured via `scriptorium.json`.

### Changes to config.nim

1. **Add `MattermostConfig` type** after the existing `DiscordConfig` type:
   ```nim
   MattermostConfig* = object
     enabled*: bool
     url*: string
     channelId*: string
     allowedUserIds*: seq[string]
   ```

2. **Add `mattermost` field** to the `Config` object:
   ```nim
   mattermost*: MattermostConfig
   ```

3. **Add `mattermostTokenPresent` proc** — returns whether `MATTERMOST_TOKEN` env var is set (mirrors `discordTokenPresent`).

4. **Update `defaultConfig`** — add default mattermost config: `MattermostConfig(enabled: false, url: "", channelId: "", allowedUserIds: @[])`.

5. **Update `loadConfig`** — add mattermost config merging, following the same pattern as the discord block. Check `raw.contains("\"mattermost\"")`, then merge `enabled`, `url`, `channelId`, and `allowedUserIds` from parsed config.

### Unit tests

Add tests to `tests/test_config.nim` for:
- Default mattermost config values.
- `mattermostTokenPresent` with and without the env var set.
- Loading mattermost config from JSON (enabled, url, channelId, allowedUserIds).

### Coding conventions

- Follow Nim import style: one block, bracket syntax, std/ first.
- Doc comments (`##`) on every proc.
- Use `jsony` for JSON deserialization (already imported in config.nim).

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0075-0075-add-mattermostconfig-to-confignim

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 11
- reasoning: Single-file addition of a config type, field, proc, and default mirroring an existing pattern (DiscordConfig), plus straightforward unit tests in one test file — one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0075/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0075/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. The only missing piece was the `mattermostTokenPresent` proc and its test — the rest of the ticket (type, field, default, loadConfig merging, and other tests) was already implemented. Added:

- `mattermostTokenPresent*()` proc in `config.nim:142-144` mirroring `discordTokenPresent`
- `testMattermostTokenPresent` test in `test_config.nim` verifying behavior with/without the `MATTERMOST_TOKEN` env var
```

### Agent Stdout Tail
```text
":14,"result":"Done. The only missing piece was the `mattermostTokenPresent` proc and its test — the rest of the ticket (type, field, default, loadConfig merging, and other tests) was already implemented. Added:\n\n- `mattermostTokenPresent*()` proc in `config.nim:142-144` mirroring `discordTokenPresent`\n- `testMattermostTokenPresent` test in `test_config.nim` verifying behavior with/without the `MATTERMOST_TOKEN` env var","stop_reason":"end_turn","session_id":"b5003746-16f6-48d4-b390-e92346b6efa4","total_cost_usd":0.3522205,"usage":{"input_tokens":15,"cache_creation_input_tokens":22592,"cache_read_input_tokens":301041,"output_tokens":2417,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":22592,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":15,"outputTokens":2417,"cacheReadInputTokens":301041,"cacheCreationInputTokens":22592,"webSearchRequests":0,"costUSD":0.3522205,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"630563a6-1006-422f-adc7-70bf43b28623"}
```
