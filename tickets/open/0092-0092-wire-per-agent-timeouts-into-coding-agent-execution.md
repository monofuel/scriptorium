# 0092 Wire per-agent timeouts into coding agent execution

**Area:** config-testing
**Priority:** medium
**Depends:** 0091

## Context

After ticket 0091 adds per-agent timeout fields to `AgentConfig`, the coding agent execution path needs to read timeouts from `config.agents.coding` instead of the global `config.timeouts` fields. This completes the per-agent timeout migration for the coding role.

## Task

1. In `src/scriptorium/agent_runner.nim` (and any other files that read `config.timeouts.codingAgentHardTimeoutMs`, `config.timeouts.codingAgentNoOutputTimeoutMs`, or `config.timeouts.codingAgentProgressTimeoutMs`), update references to read from `config.agents.coding.hardTimeout`, `config.agents.coding.noOutputTimeout`, and `config.agents.coding.progressTimeout` instead.
   - Use `grep` to find all references to `codingAgentHardTimeoutMs`, `codingAgentNoOutputTimeoutMs`, `codingAgentProgressTimeoutMs` across `src/`.
2. Keep `config.timeouts.codingAgentMaxAttempts` as-is — max attempts is not part of the per-agent timeout spec.
3. Update any tests in `tests/` that reference the global timeout fields to use the per-agent fields where appropriate.
4. Run `make test` and confirm all tests pass.

## Acceptance criteria

- Coding agent execution reads timeouts from `config.agents.coding.{hardTimeout, noOutputTimeout, progressTimeout}`.
- No remaining references to global `codingAgentHardTimeoutMs` / `codingAgentNoOutputTimeoutMs` / `codingAgentProgressTimeoutMs` in the execution path (config loading can keep them for backward compat).
- All unit tests pass.
