# 0101-add-audit-role-to-agent-config

**Area:** harness-backends

## Summary

Add the `audit` agent role to `AgentConfigs` in `src/scriptorium/config.nim` and wire it through config loading, per Section 13 and Section 19 of the spec.

## Context

The spec defines five agent roles under `scriptorium.json` `agents`: `architect`, `coding`, `manager`, `review` (currently `reviewer`), and `audit`. The `audit` role is missing from the codebase entirely. The spec says its default model should be `claude-haiku-4-5-20251001` (cheap/small for cost efficiency).

## Requirements

1. Add an `audit` field of type `AgentConfig` to the `AgentConfigs` object in `src/scriptorium/config.nim`.
2. Add a `DefaultAuditModel` constant set to `"claude-haiku-4-5-20251001"`.
3. Initialize the `audit` field in `defaultConfig()` using `defaultAgentConfig(DefaultAuditModel)`.
4. Add a `mergeAgentConfig(result.agents.audit, parsed.agents.audit)` call in `loadConfig()`.
5. Add unit tests in `tests/test_scriptorium.nim` covering:
   - Default config has audit model set to `claude-haiku-4-5-20251001` and harness `claude-code`.
   - Loading a `scriptorium.json` with `agents.audit.model` set to a non-claude model correctly infers the harness.
   - `inferHarness` works for the default audit model.

## Notes

- The config uses `jsony` for JSON deserialization.
- Follow existing patterns in the file for `architect`/`coding`/`manager`/`reviewer`.
