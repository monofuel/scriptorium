# 0091-test-audit-agent-config

**Area:** config-testing
**Depends:** 0090

## Summary

Add unit tests for the new `agents.audit` config key to ensure it loads,
merges, and defaults correctly — matching the existing test patterns for
architect/coding/manager/reviewer.

## What to do

In `tests/test_scriptorium.nim`, inside the `"config"` suite, add these tests:

1. **"defaults include audit agent config"** — verify `defaultConfig().agents.audit`
   has model `"claude-sonnet-4-6"`, harness `harnessClaudeCode`, empty
   `reasoningEffort`.

2. **"loads audit config from scriptorium.json"** — write a config with a custom
   audit model/harness/reasoningEffort, load it, and verify all three fields.

3. **"audit model remains independent when audit is unset"** — write a config that
   sets coding but leaves audit as `AgentConfig()`, load it, and verify audit
   still has the default model.

## Verification

Run `make test`. The new tests must pass.

## Notes

- Follow the existing test patterns (use `writeScriptoriumConfig`, `getTempDir`,
  `defer: removeDir`). See the "loads from scriptorium.json" and "manager model
  remains independent" tests for reference.
