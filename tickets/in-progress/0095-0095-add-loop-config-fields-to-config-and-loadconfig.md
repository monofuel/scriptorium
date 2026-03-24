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

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 24s

**Review Reasoning:** I'll review the diff against the ticket requirements, conventions, and spec.

Let me first verify the `submit_review` tool is available, and also read the relevant source files for full context.
The diff is clean and matches all ticket requirements. Let me verify:

1. **LoopConfig type** with `enabled: bool`, `feedback: string`, `goal: string`, `maxIterations: int` — all present with correct types.
2. **`loop*: LoopConfig`** added to `Config` — correct.
3. **`defaultConfig()`** sets `LoopConfig(enabled: false, feedback: "", goal: "", maxIterations: 0)` — matches requirement.
4. **`loadConfig()`** merging logic uses `raw.contains("\"loop\"")` for `enabled`, `.len > 0` for strings, `> 0` for `maxIterations` — matches the specified merge behavior.
5. **Tests** cover both absent-key defaults and full JSON parsing.

**Convention checks:** PascalCase type name, camelCase fields, no new imports needed, no try/catch, no comments-before-functions issues. All clean.

**Spec compliance:** All four keys from §16 (`loop.enabled`, `loop.goal`, `loop.feedback`, `loop.maxIterations`) with correct defaults.

**Code quality:** No dead code, no unused imports, no unrelated changes.
Approved. The implementation is clean, matches all ticket requirements, follows project conventions, and the tests cover the required cases.
