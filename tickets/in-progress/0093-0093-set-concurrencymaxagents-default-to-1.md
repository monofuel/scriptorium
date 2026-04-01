# 0093 Set concurrency.maxAgents default to 1

**Area:** config-testing
**Priority:** low

## Context

The spec (V5, Section 24) defines `concurrency.maxAgents` with a default of 1. The current `defaultConfig()` in `src/scriptorium/config.nim` sets `maxAgents: 4`. This should be corrected to match the spec default.

## Task

1. In `src/scriptorium/config.nim`, change the `maxAgents` default in `defaultConfig()` from `4` to `1`.
2. Update `tests/test_config.nim`:
   - In `testDefaultConfigValues`, change the assertion from `cfg.concurrency.maxAgents == 4` to `cfg.concurrency.maxAgents == 1`.
   - In `testPartialJsonMerge`, change the assertion from `cfg.concurrency.maxAgents == 4` to `cfg.concurrency.maxAgents == 1`.
   - In `testDashboardConfigLoading`, change the assertion from `cfg.concurrency.maxAgents == 4` to `cfg.concurrency.maxAgents == 1`.
3. Check for any other test files that assert `maxAgents == 4` and update them.
4. Run `make test` and confirm all tests pass.

## Acceptance criteria

- `defaultConfig().concurrency.maxAgents == 1`.
- All unit tests updated and passing.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0093-0093-set-concurrencymaxagents-default-to-1
