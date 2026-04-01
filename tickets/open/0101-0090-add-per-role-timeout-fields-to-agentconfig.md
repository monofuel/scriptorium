# 0090 — Add per-role timeout fields to AgentConfig

**Area:** harness-backends
**Priority:** medium

## Problem

The spec (Section 9) requires each agent role to support `hardTimeout`, `noOutputTimeout`, and `progressTimeout` fields in `scriptorium.json` under `agents.<role>`. Currently `AgentConfig` in `src/scriptorium/config.nim` only has `harness`, `model`, and `reasoningEffort`. Timeouts are stored in a separate global `TimeoutConfig` object that is coding-agent-specific.

## Task

1. Add three new fields to the `AgentConfig` type in `src/scriptorium/config.nim`:
   - `hardTimeout*: int` (milliseconds, 0 = no timeout)
   - `noOutputTimeout*: int` (milliseconds, 0 = no timeout)
   - `progressTimeout*: int` (milliseconds, 0 = no timeout)

2. Update `defaultAgentConfig` to accept timeout defaults as parameters, or update `defaultConfig()` to set role-specific timeout defaults:
   - **architect**: noOutputTimeout 600000, hardTimeout 7200000, progressTimeout 0
   - **coding**: noOutputTimeout 300000, hardTimeout 14400000, progressTimeout 600000
   - **manager**: noOutputTimeout 300000, hardTimeout 3600000, progressTimeout 0
   - **reviewer**: noOutputTimeout 300000, hardTimeout 3600000, progressTimeout 0
   - **audit**: keep at 0 (unchanged behavior)

3. Update `mergeAgentConfig` to merge parsed timeout fields when they are > 0.

4. Add unit tests in `tests/test_config.nim` verifying:
   - Default config has the expected per-role timeout values.
   - Loading a `scriptorium.json` with per-role timeouts correctly overrides defaults.
   - Zero-value timeouts in JSON do not override non-zero defaults.

Use `jsony` for JSON parsing (already in use).
