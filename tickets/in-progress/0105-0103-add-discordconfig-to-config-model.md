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
