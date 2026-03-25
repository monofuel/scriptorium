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

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0103/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0103/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes in `src/scriptorium/config.nim`:

- Added `DiscordConfig*` object type with `enabled`, `channelId`, and `allowedUsers` fields
- Added `discord*: DiscordConfig` field to `Config`
- Set defaults in `defaultConfig()` (enabled=false, empty channelId, empty allowedUsers)
- Added merge logic in `loadConfig()` gated on `raw.contains("\"discord\"")`
- Added `discordTokenPresent*()` proc that checks `DISCORD_TOKEN` env var
```

### Agent Stdout Tail
```text
 Added `DiscordConfig*` object type with `enabled`, `channelId`, and `allowedUsers` fields\n- Added `discord*: DiscordConfig` field to `Config`\n- Set defaults in `defaultConfig()` (enabled=false, empty channelId, empty allowedUsers)\n- Added merge logic in `loadConfig()` gated on `raw.contains(\"\\\"discord\\\"\")`\n- Added `discordTokenPresent*()` proc that checks `DISCORD_TOKEN` env var","stop_reason":"end_turn","session_id":"57009130-e892-4f92-b687-75b7c0c98469","total_cost_usd":0.36520874999999997,"usage":{"input_tokens":17,"cache_creation_input_tokens":26127,"cache_read_input_tokens":276510,"output_tokens":2543,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":26127},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":17,"outputTokens":2543,"cacheReadInputTokens":276510,"cacheCreationInputTokens":26127,"webSearchRequests":0,"costUSD":0.36520874999999997,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"63c69716-78d0-49df-8988-3701392b714a"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 18s

**Review Reasoning:** Looking at the diff against the ticket requirements and project conventions.

**Ticket requirements check:**
1. `DiscordConfig` object type with `enabled`, `channelId`, `allowedUsers` fields — ✅
2. `discord*: DiscordConfig` field on `Config` — ✅
3. Defaults in `defaultConfig()` — ✅
4. Merge logic gated on `raw.contains("\"discord\"")` — ✅
5. `discordTokenPresent*()` proc checking env var — ✅
6. Nim conventions followed — ✅

**Convention check:**
- Naming: PascalCase for type (`DiscordConfig`), camelCase for fields — ✅
- Doc comment on `discordTokenPresent` proc — ✅
- No new imports needed — ✅
- No try/catch, no boolean error returns — ✅
- Follows existing patterns (mirrors `LoopConfig` structure) — ✅

**Spec compliance:**
- `discord.enabled` (boolean, default false) — ✅
- `discord.channelId` (string) — ✅
- `discord.allowedUsers` (array of strings) — ✅
- `DISCORD_TOKEN` not stored in config — ✅

**Code quality:**
- No dead code, no unused imports, no leftover artifacts — ✅
- Changes are scoped to exactly what the ticket requires — ✅

Clean implementation that follows existing patterns precisely. No issues found.
Approved. The implementation cleanly follows the existing `LoopConfig` pattern, satisfies all ticket requirements, and adheres to project conventions.
