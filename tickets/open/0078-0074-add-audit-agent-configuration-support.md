<!-- file: tickets/open/0074-audit-agent-config.md -->
# 0074 — Add audit agent configuration support

**Area:** audit-agent

Add `audit` to the agent configuration system in `scriptorium.json`.

## Details

In `src/scriptorium/config.nim`:

1. Add a `DefaultAuditModel` constant set to `"claude-haiku-4-5-20251001"`.
2. Add `audit*: AgentConfig` to the `AgentConfigs` object.
3. In `defaultConfig()`, initialize `audit` with `defaultAgentConfig(DefaultAuditModel)`.
4. In `loadConfig()`, add merge logic for `agents.audit` matching the existing pattern for other agent types (harness, model, reasoningEffort).

In `scriptorium.json`, add the audit agent config block:
```json
"audit": {
  "model": "claude-haiku-4-5-20251001"
}
