# 0074 Add Mattermost configuration support

**Area:** config-testing

## Summary

Add Mattermost notification configuration to the config system, mirroring the existing Discord config pattern.

## Requirements

1. In `src/scriptorium/config.nim`:
   - Add a `MattermostConfig` object type with fields: `enabled: bool`, `url: string`, `channelId: string`, `allowedUserIds: seq[string]`.
   - Add a `mattermost: MattermostConfig` field to the `Config` object.
   - Initialize `mattermost` in `defaultConfig()` with `enabled: false`, empty strings, and empty seq (same pattern as `DiscordConfig`).
   - Add merge logic in `loadConfig` for the `mattermost` section, guarded by `raw.contains("\"mattermost\"")`, following the same pattern as the `discord` merge block.

2. In `tests/test_config.nim`:
   - Add `testDefaultMattermostConfig`: verify `defaultConfig().mattermost.enabled == false`, empty url/channelId/allowedUserIds.
   - Add `testMattermostConfigLoading`: write a JSON with `mattermost` section, verify all fields load correctly.
   - Add `testMattermostPartialConfig`: verify partial mattermost JSON only overrides specified fields.
   - Register all new test procs in `isMainModule`.

## Notes

- Use `jsony` for JSON deserialization (already imported in config.nim).
- Follow existing Discord config as the exact pattern to copy.
- This ticket only covers config loading and tests. Mattermost bot implementation is a separate area.
