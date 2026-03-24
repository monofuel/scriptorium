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
