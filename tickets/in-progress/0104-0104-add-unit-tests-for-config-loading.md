# 0104 Add unit tests for config loading

**Area:** config-testing
**Depends:** 0103

## Problem

There is no dedicated unit test file for the config module (`src/scriptorium/config.nim`). Config loading, default values, JSON merging, and environment variable overrides are untested in isolation.

## Requirements

Create `tests/test_config.nim` with the following test cases:

1. **Default config values** — Call `defaultConfig()` and verify all default values: agent models, harnesses, endpoints, concurrency (maxAgents=4, tokenBudgetMB=0), loop (enabled=false), discord (enabled=false, empty channelId, empty allowedUsers), log levels (empty strings).
2. **Missing config file** — Call `loadConfig()` with a temp directory that has no `scriptorium.json`. Verify it returns the default config.
3. **Partial JSON merge** — Write a minimal `scriptorium.json` (e.g. only `{"agents": {"coding": {"model": "custom-model"}}}`) to a temp dir, call `loadConfig()`, verify the specified field is overridden and all other fields retain defaults.
4. **Full JSON merge** — Write a `scriptorium.json` with all sections populated (agents, endpoints, concurrency, timeouts, loop, discord), call `loadConfig()`, verify all values are correctly loaded.
5. **Environment variable override for logLevel** — Set `SCRIPTORIUM_LOG_LEVEL` env var, write a config with a different `logLevel`, call `loadConfig()`, verify the env var wins. Clean up the env var after the test.
6. **Environment variable override for fileLogLevel** — Same as above for `SCRIPTORIUM_FILE_LOG_LEVEL`.
7. **Discord config loading** — Write a `scriptorium.json` with discord section, verify enabled, channelId, and allowedUsers are loaded correctly.
8. **discordTokenPresent** — Set/unset `DISCORD_TOKEN` env var and verify `discordTokenPresent()` returns the expected boolean.
9. **resolveModel with and without CLAUDE_CODE_USE_BEDROCK** — Verify model ID translation works.
10. **inferHarness** — Verify claude- prefix maps to claude-code, codex-/gpt- to codex, other to typoi.

Use `jsony` for writing test JSON files. Use `std/os` for temp directories and env vars. Use `std/tempfiles` or create temp dirs manually. Follow existing test patterns in the repo (e.g. `test_loop_system.nim`).

## Acceptance criteria

- `tests/test_config.nim` exists and covers all listed cases.
- `nim r tests/test_config.nim` passes.
- `make test` passes (the new file matches the `tests/test_*.nim` glob).
- No mocks or fakes — this tests the real `loadConfig` against temp files.

## Files to create

- `tests/test_config.nim`

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0104-0104-add-unit-tests-for-config-loading
