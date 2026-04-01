# 0091 Add per-agent timeout fields to AgentConfig

**Area:** config-testing
**Priority:** medium

## Context

The area spec lists `agents.architect.{hardTimeout, noOutputTimeout, progressTimeout}` (and the same for coding, manager, reviewer) as supported config keys. Currently, timeouts are only defined globally under `TimeoutConfig` with coding-agent-specific field names. The config layer needs per-agent timeout fields so each role can have independent timeout settings.

## Task

1. In `src/scriptorium/config.nim`, add three new fields to the `AgentConfig` type:
   ```nim
   hardTimeout*: int
   noOutputTimeout*: int
   progressTimeout*: int
   ```
2. Update `defaultAgentConfig` to set default values for these fields. Use the same defaults currently in `TimeoutConfig`:
   - `hardTimeout: 14_400_000` (4 hours)
   - `noOutputTimeout: 300_000` (5 minutes)
   - `progressTimeout: 600_000` (10 minutes)
3. Update `mergeAgentConfig` to merge these fields when non-zero:
   ```nim
   if parsed.hardTimeout > 0:
     base.hardTimeout = parsed.hardTimeout
   if parsed.noOutputTimeout > 0:
     base.noOutputTimeout = parsed.noOutputTimeout
   if parsed.progressTimeout > 0:
     base.progressTimeout = parsed.progressTimeout
   ```
4. Do NOT remove the global `TimeoutConfig` or its loading — keep it for backward compatibility. The per-agent fields take precedence when set; consumers will be migrated in a follow-up ticket.
5. Add unit tests in `tests/test_config.nim`:
   - `testPerAgentTimeoutDefaults`: verify `defaultConfig().agents.coding.hardTimeout == 14_400_000`, same for other fields and roles.
   - `testPerAgentTimeoutOverride`: write a config JSON with `"agents": {"coding": {"hardTimeout": 5000}}`, load it, assert `cfg.agents.coding.hardTimeout == 5000` and other roles still have defaults.
   - `testPerAgentTimeoutFullOverride`: write a config JSON setting all three timeout fields on architect, verify all load correctly.
6. Register new test procs in the `when isMainModule` block.
7. Run `make test` and confirm all tests pass.

## Acceptance criteria

- `AgentConfig` has `hardTimeout`, `noOutputTimeout`, `progressTimeout` int fields.
- `mergeAgentConfig` merges non-zero parsed values into base.
- Default values match current global timeout defaults.
- Global `TimeoutConfig` is preserved (not removed).
- New unit tests pass.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0091-0091-add-per-agent-timeout-fields-to-agentconfig
