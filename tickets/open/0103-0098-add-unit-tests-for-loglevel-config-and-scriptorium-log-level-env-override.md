# 0098 — Add unit tests for logLevel config and SCRIPTORIUM_LOG_LEVEL env override

**Area:** config-testing

## Problem

`loadConfig` in `src/scriptorium/config.nim` reads `logLevel` from the config file and overrides it with the `SCRIPTORIUM_LOG_LEVEL` environment variable. Similarly, `fileLogLevel` is read from config and overridden by `SCRIPTORIUM_FILE_LOG_LEVEL`. None of this logic has unit test coverage.

## Requirements

Add tests in `tests/test_scriptorium.nim` that verify:

1. **logLevel from config file** — Write a `scriptorium.json` with `"logLevel": "debug"`, call `loadConfig`, assert `result.logLevel == "debug"`.
2. **fileLogLevel from config file** — Write a `scriptorium.json` with `"fileLogLevel": "warn"`, call `loadConfig`, assert `result.fileLogLevel == "warn"`.
3. **SCRIPTORIUM_LOG_LEVEL env override** — Write a config with `"logLevel": "info"`, set `SCRIPTORIUM_LOG_LEVEL` env var to `"debug"` using `putEnv`, call `loadConfig`, assert `result.logLevel == "debug"`. Restore/clear the env var after the test with `delEnv`.
4. **SCRIPTORIUM_FILE_LOG_LEVEL env override** — Same pattern as above for the file log level env var.
5. **Default when absent** — Load a config with no logLevel key, assert `result.logLevel == ""` (empty string default).

Use jsony for serialization. Follow existing test patterns. Use `putEnv`/`delEnv` from `std/os` for env var manipulation.
