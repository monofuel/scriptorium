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
