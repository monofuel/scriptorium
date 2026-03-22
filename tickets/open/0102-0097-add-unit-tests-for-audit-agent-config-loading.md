# 0097 — Add unit tests for audit agent config loading

**Area:** config-testing
**Depends:** 0096

## Problem

After 0096 adds the `audit` field to `AgentConfigs`, there are no tests verifying it loads correctly from `scriptorium.json`.

## Requirements

Add tests in `tests/test_scriptorium.nim` (inside the existing config test suite) that verify:

1. **Explicit audit config** — Write a `scriptorium.json` with `agents.audit` set to a non-default model/harness/reasoningEffort, call `loadConfig`, and assert all three fields match.
2. **Default fallback** — Load a config with no `agents.audit` key and assert audit defaults match `defaultConfig().agents.audit`.
3. **Harness inference** — Set audit model to a non-claude model (e.g. `"grok-code-fast-1"`) without setting harness, and verify harness is inferred as `harnessTypoi`.

Use jsony for serialization. Follow the existing test patterns (create a temp dir, write `scriptorium.json`, call `loadConfig`).
