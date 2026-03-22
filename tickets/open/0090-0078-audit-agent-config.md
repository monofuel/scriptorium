# 0078-audit-agent-config

**Area:** audit-agent

## Description

Add `audit` field to `AgentConfigs` in `src/scriptorium/config.nim` so that `scriptorium.json` can configure the audit agent via `agents.audit`.

### Requirements

- Add an `audit` field of type `AgentConfig` to the `AgentConfigs` object in `src/scriptorium/config.nim`.
- Set defaults: model `claude-haiku-4-5-20251001`, harness `claude-code`, empty `reasoningEffort`.
- Add a `DefaultAuditModel` constant set to `"claude-haiku-4-5-20251001"`.
- In `defaultConfig()`, initialize `agents.audit` using `defaultAgentConfig(DefaultAuditModel)`.
- In `loadConfig()`, call `mergeAgentConfig(result.agents.audit, parsed.agents.audit)` alongside the other agent configs.
- Add a unit test in a new or existing test file that verifies:
  - Default config has audit model = `claude-haiku-4-5-20251001`.
  - A `scriptorium.json` with `agents.audit.model` set to a custom value overrides the default.

### Context

The audit agent is a read-only background agent. This ticket only adds configuration support — the agent itself is built in subsequent tickets.

Existing pattern to follow: see how `architect`, `coding`, `manager`, and `reviewer` configs are defined and merged in `src/scriptorium/config.nim`.
