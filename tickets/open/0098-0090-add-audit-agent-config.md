# 0090-add-audit-agent-config

**Area:** config-testing

## Summary

Add the `agents.audit` config key to the config module so the audit agent role
can be configured in `scriptorium.json` alongside architect, coding, manager,
and reviewer.

## What to do

1. In `src/scriptorium/config.nim`:
   - Add `audit*: AgentConfig` field to the `AgentConfigs` object (after `reviewer`).
   - Add a `DefaultAuditModel` constant (use `"claude-sonnet-4-6"`).
   - Populate `result.agents.audit` in `defaultConfig()` using `defaultAgentConfig(DefaultAuditModel)`.
   - Add a `mergeAgentConfig(result.agents.audit, parsed.agents.audit)` call in `loadConfig`.

2. In `scriptorium.json` (project root): no change needed — the file only lists
   overrides and audit will fall back to defaults.

3. Do **not** change any other module. This ticket only adds the config plumbing.

## Verification

Run `make test`. All existing config tests must still pass. Confirm that
`defaultConfig().agents.audit.model == "claude-sonnet-4-6"` and
`defaultConfig().agents.audit.harness == harnessClaudeCode`.

## Notes

- Use `jsony` for JSON serialization (already imported in config.nim).
- Follow the exact same pattern used for the other four agent roles.
