# 0103 — Add DiscordConfig to config model

**Area:** discord

## Description

Add a `DiscordConfig` type to `src/scriptorium/config.nim` and wire it into `Config`, `defaultConfig`, and `loadConfig`.

### Requirements

1. Add a new type:
```nim
DiscordConfig* = object
  channelId*: string
  allowedUsers*: seq[string]
```

2. Add `discord*: DiscordConfig` field to the `Config` object.

3. In `defaultConfig()`, initialize with empty defaults: `discord: DiscordConfig(channelId: "", allowedUsers: @[])`.

4. In `loadConfig()`, merge parsed discord fields into result when the `"discord"` key is present in raw JSON (same pattern as the `"loop"` merge block).

5. The bot token is read from the `DISCORD_TOKEN` environment variable at runtime — it is **never** stored in config. Do not add a token field.

6. Add a unit test in `tests/test_config.nim` (or create it if absent) that verifies:
   - `defaultConfig().discord.channelId == ""`
   - `defaultConfig().discord.allowedUsers.len == 0`
   - A JSON config with a discord section round-trips through `loadConfig` correctly.

### Notes

- Use `jsony` for JSON deserialization (already imported in config.nim).
- Follow existing merge patterns — check `raw.contains("\"discord\"")` before merging.
- Constants use PascalCase, variables use camelCase.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0105-0103-add-discordconfig-to-config-model

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 10
- reasoning: Single-file type addition and config wiring following an existing pattern (loop merge block), plus a straightforward unit test — one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0105/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0105/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes submitted:

- **`src/scriptorium/config.nim`**: Added `DiscordConfig` type with `channelId` and `allowedUsers` fields, added `discord` field to `Config`, initialized in `defaultConfig()`, and added merge block in `loadConfig()` following the existing loop pattern.
- **`tests/test_config.nim`**: New unit test verifying empty defaults and JSON round-trip through `loadConfig`.

Rebase conflicts (master had a partial `DiscordConfig` with an `enabled` field) were resolved per ticket spec — no `enabled` field, no token field.
```

### Agent Stdout Tail
```text
dded `discord` field to `Config`, initialized in `defaultConfig()`, and added merge block in `loadConfig()` following the existing loop pattern.\n- **`tests/test_config.nim`**: New unit test verifying empty defaults and JSON round-trip through `loadConfig`.\n\nRebase conflicts (master had a partial `DiscordConfig` with an `enabled` field) were resolved per ticket spec — no `enabled` field, no token field.","stop_reason":"end_turn","session_id":"39ede788-b33b-4ddb-bf89-f0753f50e1e8","total_cost_usd":0.6588505,"usage":{"input_tokens":183,"cache_creation_input_tokens":34716,"cache_read_input_tokens":617821,"output_tokens":5282,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":34716},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":183,"outputTokens":5282,"cacheReadInputTokens":617821,"cacheCreationInputTokens":34716,"webSearchRequests":0,"costUSD":0.6588505,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"d668c15d-4f2a-474d-bc50-6f3a57067923"}
```
