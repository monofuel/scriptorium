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

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 26s

**Review Reasoning:** Let me verify the claims that most of the ticket work was already in place before reviewing.
Everything checks out. The agent's claim is correct — the MattermostConfig type, Config field, defaultConfig, loadConfig merging, and most tests were already in place. The diff only adds the `mattermostTokenPresent` proc and its test, which were the missing pieces.

Let me verify the code and tests against all ticket requirements:

1. **MattermostConfig type** (line 47-51) - present with correct fields
2. **mattermost field** in Config (line 86) - present
3. **mattermostTokenPresent proc** (lines 142-144) - added in diff, mirrors `discordTokenPresent`
4. **defaultConfig** (line 132) - present with correct defaults
5. **loadConfig** (lines 213-220) - present, follows discord pattern
6. **Tests**: default config (line 234), loading from JSON (line 243), partial config (line 259), token present (line 275) - all present

Convention checks:
- Import style: correct (single block, bracket syntax, std/ first)
- Doc comments: present on both the proc and test proc, complete sentences with punctuation
- Naming: camelCase for the proc, follows existing patterns
- No try/catch, no boolean error returns
- Test mirrors `testDiscordTokenPresent` structure exactly

No issues found. Let me submit the review.
All ticket requirements are met. The diff cleanly adds `mattermostTokenPresent` and its test, mirroring the existing `discordTokenPresent` pattern. The pre-existing code (type, field, defaults, loadConfig merging, other tests) was already in place and correct. No convention violations, no spec deviations, no dead code.

## Merge Queue Success
- Summary: Added mattermostTokenPresent proc to config.nim (mirrors discordTokenPresent) and corresponding unit tests in test_config.nim. The MattermostConfig type, Config field, default values, and loadConfig merging were already in place.\n
### Quality Check Output
```text
or_flow.nim]  3537 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
[tests/integration_orchestrator_flow.nim] /home/scriptorium/.cache/nim/integration_orchestrator_flow_d/@phashes.nim.c:1059:1: fatal error: error writing to /dev/shm/ccOqii80.s: No space left on device
[tests/integration_orchestrator_flow.nim]  1059 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
[tests/integration_orchestrator_flow.nim] /home/scriptorium/.cache/nim/integration_orchestrator_flow_d/@ppathnorm.nim.c:545:1: fatal error: error writing to /dev/shm/ccNYWgPE.s: No space left on device
[tests/integration_orchestrator_flow.nim]   545 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
[tests/integration_orchestrator_flow.nim] /home/scriptorium/.cache/nim/integration_orchestrator_flow_d/@pparsejson.nim.c:1555:1: fatal error: error writing to /dev/shm/ccVcLwGl.s: No space left on device
[tests/integration_orchestrator_flow.nim]  1555 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
[tests/integration_orchestrator_flow.nim] /home/scriptorium/.cache/nim/integration_orchestrator_flow_d/@ptables.nim.c:8698:1: fatal error: error writing to /dev/shm/cc88X3F7.s: No space left on device
[tests/integration_orchestrator_flow.nim]  8698 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
[tests/integration_orchestrator_flow.nim] /home/scriptorium/.cache/nim/integration_orchestrator_flow_d/@psystem.nim.c:14352:1: fatal error: error writing to /dev/shm/cc8i3TbK.s: No space left on device
[tests/integration_orchestrator_flow.nim] 14352 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
```

## Metrics
- wall_time_seconds: 215
- coding_wall_seconds: 56
- test_wall_seconds: 16
- attempt_count: 1
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 126892

## Post-Analysis
- actual_difficulty: trivial
- prediction_accuracy: overestimated
- brief_summary: Predicted easy, actual was trivial with 1 attempt(s) in 3m35s.
