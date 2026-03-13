# Add Concurrency Config Keys To scriptorium.json

**Area:** config-testing

## Problem

The `Config` type in `config.nim` does not include a `concurrency` field. The V5 spec (§24, §26) requires two new config keys:

- `concurrency.maxAgents` (integer, default 1) — maximum number of parallel coding agents.
- `concurrency.tokenBudgetMB` (optional integer megabytes) — cumulative session stdout byte budget.

These keys are listed in the config-testing area scope but are not yet implemented.

## Requirements

1. Add a `ConcurrencyConfig` object type with fields:
   - `maxAgents*: int` (default 1)
   - `tokenBudgetMB*: int` (default 0, meaning unlimited)
2. Add `concurrency*: ConcurrencyConfig` field to the `Config` type.
3. Initialize with defaults in `defaultConfig()` or equivalent.
4. Parse `concurrency.maxAgents` and `concurrency.tokenBudgetMB` from `scriptorium.json` in `loadConfig()`.
5. Add unit test in `tests/test_scriptorium.nim` verifying:
   - Default values when `concurrency` key is absent.
   - Correct parsing when both keys are present.
   - Correct parsing when only `maxAgents` is present.

## Acceptance Criteria

- `make test` passes with new tests.
- Config struct is available for use by parallel-execution implementation.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0045-concurrency-config-keys
