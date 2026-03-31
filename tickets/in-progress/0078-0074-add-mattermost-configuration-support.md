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

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0078-0074-add-mattermost-configuration-support

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 10
- reasoning: Straightforward pattern-copy from existing Discord config: add one object type, one field, one default, one merge block in config.nim, plus three simple tests in test_config.nim — all following an explicit existing template.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0078/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0078/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes:

- **`src/scriptorium/config.nim`**: Added `MattermostConfig` type with `enabled`, `url`, `channelId`, `allowedUserIds` fields. Added `mattermost` field to `Config`, initialized in `defaultConfig()`, and added merge logic in `loadConfig` guarded by `raw.contains("\"mattermost\"")`.
- **`tests/test_config.nim`**: Added `testDefaultMattermostConfig`, `testMattermostConfigLoading`, and `testMattermostPartialConfig` — all passing.
```

### Agent Stdout Tail
```text
nim`**: Added `MattermostConfig` type with `enabled`, `url`, `channelId`, `allowedUserIds` fields. Added `mattermost` field to `Config`, initialized in `defaultConfig()`, and added merge logic in `loadConfig` guarded by `raw.contains(\"\\\"mattermost\\\"\")`.\n- **`tests/test_config.nim`**: Added `testDefaultMattermostConfig`, `testMattermostConfigLoading`, and `testMattermostPartialConfig` — all passing.","stop_reason":"end_turn","session_id":"9d31320c-a0b3-4ada-915e-731864cb003f","total_cost_usd":0.5149669999999998,"usage":{"input_tokens":18,"cache_creation_input_tokens":30152,"cache_read_input_tokens":479104,"output_tokens":3475,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":30152,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":18,"outputTokens":3475,"cacheReadInputTokens":479104,"cacheCreationInputTokens":30152,"webSearchRequests":0,"costUSD":0.5149669999999998,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"71a12aeb-d8df-43aa-bdce-d37059661d39"}
```
