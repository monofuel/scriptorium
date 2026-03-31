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
