# 0104 — Add audit role to AgentConfigs

**Area:** harness-backends

## Problem

The spec (sections 13 and 19) requires `agents.audit` in `scriptorium.json` with `harness`, `model`, and `reasoningEffort` fields. The `AgentConfigs` type in `src/scriptorium/config.nim` only has `architect`, `coding`, `manager`, and `reviewer` — no `audit` field.

## Requirements

1. Add an `audit*: AgentConfig` field to the `AgentConfigs` object in `src/scriptorium/config.nim`.
2. Set the default audit model to `claude-haiku-4-5-20251001` in `defaultConfig()` (spec section 19 says "default Haiku").
3. Add a `mergeAgentConfig` call for `result.agents.audit` / `parsed.agents.audit` in `loadConfig`.
4. Add a unit test in `tests/test_scriptorium.nim` that loads a `scriptorium.json` with `agents.audit` configured and verifies the model and harness are loaded correctly.
5. Add a unit test that verifies the default audit config uses model `claude-haiku-4-5-20251001` and harness `claude-code` (inferred from the `claude-` prefix).

## Key files

- `src/scriptorium/config.nim` — `AgentConfigs`, `defaultConfig`, `loadConfig`
- `tests/test_scriptorium.nim` — existing config test suite

## Notes

- Use `jsony` for JSON parsing (already imported in config.nim).
- The harness for haiku should be auto-inferred via `inferHarness("claude-haiku-4-5-20251001")` which returns `harnessClaudeCode`.
