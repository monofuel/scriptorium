# 0108 — Add audit agent role to config

**Area:** harness-backends

## Problem

The spec (section 19) requires an `agents.audit` role in `scriptorium.json` with:
- Default model: `claude-haiku-4-5-20251001`
- Support for `harness`, `model`, and `reasoningEffort` (same as other roles)

Currently `AgentConfigs` in `src/scriptorium/config.nim` only has `architect`, `coding`, `manager`, and `reviewer`. The audit role is completely absent from config types, defaults, and merge logic.

## Changes

1. **`src/scriptorium/config.nim`**:
   - Add `DefaultAuditModel = "claude-haiku-4-5-20251001"` constant.
   - Add `audit*: AgentConfig` field to `AgentConfigs`.
   - Add `audit: defaultAgentConfig(DefaultAuditModel)` to `defaultConfig()`.
   - Add `mergeAgentConfig(result.agents.audit, parsed.agents.audit)` to `loadConfig()`.

2. **`tests/test_scriptorium.nim`**:
   - In the "defaults when file is missing" test, add checks for `cfg.agents.audit.model == "claude-haiku-4-5-20251001"` and `cfg.agents.audit.harness == harnessClaudeCode` (inferred from `claude-` prefix).
   - Add a test that loads a config with `agents.audit` overridden and verifies the merge.

3. **`scriptorium.json`** — no change needed (audit will use defaults when absent).

## Validation

- `make test` passes, including the new audit config tests.
- Existing config tests remain green (adding a field to `AgentConfigs` should not break jsony deserialization of files that omit it).
