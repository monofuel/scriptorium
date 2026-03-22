# 0098 — Add audit agent config to AgentConfigs

**Area:** config-testing

## Problem

The area scope and spec (Section 19) define `agents.audit.{harness, model, reasoningEffort}` as a supported config key, but `AgentConfigs` in `src/scriptorium/config.nim` has no `audit` field. The `loadConfig` proc does not merge audit config, and there are no tests for it.

## Task

1. Add an `audit*: AgentConfig` field to the `AgentConfigs` object in `src/scriptorium/config.nim`.
2. Set its default in `defaultConfig()` — use `DefaultCodingModel` (same as reviewer/manager) for the model default.
3. Add a `mergeAgentConfig(result.agents.audit, parsed.agents.audit)` call in `loadConfig`.
4. Add a unit test in `tests/test_scriptorium.nim` in the `"config"` suite that:
   - Writes a `scriptorium.json` with `agents.audit` set to a custom model/harness/reasoningEffort.
   - Calls `loadConfig` and asserts the audit config was loaded correctly.
5. Add a second test that confirms `defaultConfig().agents.audit` has the expected defaults.

## Notes

- Use `jsony` for JSON serialization (already imported in config.nim).
- Follow the existing pattern of other agent configs (architect, coding, manager, reviewer).
- The `writeScriptoriumConfig` helper in the test file already works for writing `Config` objects — just set the audit field before writing.
````

---

````markdown
# 0099 — Add unit tests for log level config and env overrides

**Area:** config-testing

## Problem

`loadConfig` in `src/scriptorium/config.nim:148-157` handles `logLevel`, `fileLogLevel`, `SCRIPTORIUM_LOG_LEVEL`, and `SCRIPTORIUM_FILE_LOG_LEVEL` but none of these paths have any test coverage.

## Task

Add the following tests to the `"config"` suite in `tests/test_scriptorium.nim`:

1. **logLevel from config file** — Write a `scriptorium.json` with `"logLevel": "debug"`, call `loadConfig`, assert `cfg.logLevel == "debug"`.
2. **fileLogLevel from config file** — Write a `scriptorium.json` with `"fileLogLevel": "error"`, call `loadConfig`, assert `cfg.fileLogLevel == "error"`.
3. **SCRIPTORIUM_LOG_LEVEL env overrides config** — Write a `scriptorium.json` with `"logLevel": "debug"`, set `SCRIPTORIUM_LOG_LEVEL` env var to `"warn"`, call `loadConfig`, assert `cfg.logLevel == "warn"`. Clean up the env var with `delEnv` after the test.
4. **SCRIPTORIUM_FILE_LOG_LEVEL env overrides config** — Write a `scriptorium.json` with `"fileLogLevel": "debug"`, set `SCRIPTORIUM_FILE_LOG_LEVEL` to `"error"`, call `loadConfig`, assert `cfg.fileLogLevel == "error"`. Clean up with `delEnv`.
5. **Missing logLevel returns empty string** — Load config from a dir with a minimal `scriptorium.json` (no logLevel key), assert `cfg.logLevel == ""`.

## Notes

- Use `putEnv` / `delEnv` from `std/os` (already imported in the test file).
- Use the existing `writeScriptoriumConfig` helper or write raw JSON with `writeFile` — either approach is fine.
- Follow existing test patterns: create a temp dir, write config, load, assert, clean up.
- Each test should clean up env vars it sets, even on failure — use a `defer` or `finally` block.
````
