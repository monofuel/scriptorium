# 0095 Add loop config fields to Config and loadConfig

**Area:** loop-system

Add the `loop` configuration section to `scriptorium.json` parsing.

## Requirements

1. Add a `LoopConfig` object type to `src/scriptorium/config.nim` with fields:
   - `enabled*: bool` (default `false`)
   - `feedback*: string` (the shell command to run; default `""`)
   - `goal*: string` (the optimization goal; default `""`)
   - `maxIterations*: int` (0 means unlimited; default `0`)

2. Add `loop*: LoopConfig` to the `Config` object.

3. In `defaultConfig()`, set loop to `LoopConfig(enabled: false, feedback: "", goal: "", maxIterations: 0)`.

4. In `loadConfig()`, merge parsed loop fields into the result:
   - If the raw JSON contains `"loop"`, merge each non-default field.
   - `enabled` should be merged when the `"loop"` key is present in the raw JSON (use `raw.contains("\"loop\"")` pattern, same as `syncAgentsMd`).
   - `feedback` and `goal` merge when their `.len > 0`.
   - `maxIterations` merges when `> 0`.

5. Use `jsony` for deserialization (already a project dependency).

## Acceptance

- `loadConfig` on a repo with no `loop` key returns `LoopConfig(enabled: false)`.
- `loadConfig` on `{"loop": {"enabled": true, "feedback": "make bench", "goal": "optimize latency", "maxIterations": 5}}` returns matching fields.
- Add a unit test in `tests/test_scriptorium.nim` (or a new `tests/test_config.nim`) that verifies both cases using a temp directory with a written `scriptorium.json`.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0095-0095-add-loop-config-fields-to-config-and-loadconfig

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 11
- reasoning: Single-file config struct addition with simple field merging in loadConfig, plus a straightforward unit test — all within one module, minimal integration risk.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0095/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0095/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Added `LoopConfig` to `config.nim` with all four fields, integrated it into `defaultConfig()` and `loadConfig()` using the `raw.contains("\"loop\"")` pattern, and added two unit tests covering the absent-key and full-config cases. All tests pass.
```

### Agent Stdout Tail
```text
fa3e1c46"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":66287,"duration_api_ms":63206,"num_turns":16,"result":"Done. Added `LoopConfig` to `config.nim` with all four fields, integrated it into `defaultConfig()` and `loadConfig()` using the `raw.contains(\"\\\"loop\\\"\")` pattern, and added two unit tests covering the absent-key and full-config cases. All tests pass.","stop_reason":"end_turn","session_id":"302290d6-8771-45e3-a7fa-6df1821b0009","total_cost_usd":0.4456800000000001,"usage":{"input_tokens":117,"cache_creation_input_tokens":33582,"cache_read_input_tokens":333365,"output_tokens":2741,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":33582},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":117,"outputTokens":2741,"cacheReadInputTokens":333365,"cacheCreationInputTokens":33582,"webSearchRequests":0,"costUSD":0.4456800000000001,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"bad86235-968a-4414-947d-2fad9745bc78"}
```
