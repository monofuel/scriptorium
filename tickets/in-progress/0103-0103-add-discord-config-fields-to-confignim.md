# 0103 Add Discord config fields to config.nim

**Area:** config-testing

## Problem

The area spec requires `discord.enabled`, `discord.channelId`, and `discord.allowedUsers` config keys in `scriptorium.json`, plus awareness of the `DISCORD_TOKEN` environment variable. None of these exist in `src/scriptorium/config.nim` today.

## Requirements

1. Add a `DiscordConfig` object type to `src/scriptorium/config.nim` with fields:
   - `enabled*: bool` (default `false`)
   - `channelId*: string` (default `""`)
   - `allowedUsers*: seq[string]` (default `@[]`)
2. Add a `discord*: DiscordConfig` field to the `Config` object.
3. Set discord defaults in `defaultConfig()`.
4. Add merge logic in `loadConfig()` to read discord fields from JSON (gate on `raw.contains("\"discord\"")` like `loop` does).
5. Do NOT store `DISCORD_TOKEN` in config — it stays as an env var only. But add a proc `discordTokenPresent*(): bool` that returns `getEnv("DISCORD_TOKEN").len > 0` for downstream code to check.
6. Follow existing Nim conventions: bracket imports, doc comments on every proc, PascalCase constants, camelCase variables, grouped type/const/let/var blocks.

## Acceptance criteria

- `loadConfig` correctly reads a `scriptorium.json` containing `"discord": {"enabled": true, "channelId": "123", "allowedUsers": ["456"]}` and populates the config.
- Missing discord section falls back to defaults (enabled=false, empty channelId, empty allowedUsers).
- `discordTokenPresent()` returns true/false based on the `DISCORD_TOKEN` env var.
- `make test` passes (no regressions).

## Files to modify

- `src/scriptorium/config.nim`

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0103-0103-add-discord-config-fields-to-confignim

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 10
- reasoning: Single-file change adding a new config object type and merge logic, following existing patterns (like the loop config), with straightforward defaults and a simple env-var check proc.
