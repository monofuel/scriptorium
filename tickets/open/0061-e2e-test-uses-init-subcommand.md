# Update E2E Tests To Use scriptorium init

**Area:** cli-init
**Depends:** 0054, 0056, 0057

## Problem

E2E tests in `tests/e2e_euler_live.nim` and integration tests use manual seeding
(calling `runInit()` programmatically and adding files separately) instead of
exercising the `scriptorium init` subcommand. This means the init flow is not
tested end-to-end.

## Requirements

- Update `tests/support/live_integration_support.nim` `initLiveRepo()` to use
  the `scriptorium init` subcommand via CLI invocation instead of calling
  `runInit()` directly.
- Remove manual Makefile/AGENTS.md seeding steps that are now handled by init.
- Ensure e2e tests still pass with the new init flow.
- Keep any test-specific overrides (e.g., custom Makefile targets for Euler
  problems) as post-init modifications.

## Files To Change

- `tests/support/live_integration_support.nim` — update init helper.
- `tests/e2e_euler_live.nim` — remove manual seeding if now redundant.
- `tests/integration_orchestrator_live_submit_pr.nim` — same as above.

## Acceptance Criteria

- E2E tests use `scriptorium init` CLI subcommand for setup.
- Manual seeding of AGENTS.md, Makefile, and scriptorium.json is removed where
  init now handles it.
- All e2e and integration tests pass.
