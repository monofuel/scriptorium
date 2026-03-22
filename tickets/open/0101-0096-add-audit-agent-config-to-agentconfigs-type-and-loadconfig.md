# 0096 — Add audit agent config to AgentConfigs type and loadConfig

**Area:** config-testing

## Problem

The area scope specifies `agents.audit.{harness, model, reasoningEffort}` as a supported config key, but `AgentConfigs` in `src/scriptorium/config.nim` only has `architect`, `coding`, `manager`, and `reviewer`. The `audit` field is missing from the type, `defaultConfig()`, and the merge logic in `loadConfig()`.

## Requirements

1. Add an `audit*: AgentConfig` field to the `AgentConfigs` object in `src/scriptorium/config.nim`.
2. In `defaultConfig()`, initialize `audit` with `defaultAgentConfig(DefaultArchitectModel)` (audit uses the same default model as architect).
3. In `loadConfig()`, add a `mergeAgentConfig(result.agents.audit, parsed.agents.audit)` call alongside the existing four agent merges.
4. Add `"audit": { "model": "claude-opus-4-6" }` to the `agents` block in the root `scriptorium.json`.

## Scope

- `src/scriptorium/config.nim` — type + two procs
- `scriptorium.json` — add audit entry

Do **not** add new tests in this ticket (covered by 0097).
