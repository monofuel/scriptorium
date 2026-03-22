# 0092-test-log-level-config-and-env-override

**Area:** config-testing

## Summary

Add unit tests covering log level configuration: the `logLevel` and
`fileLogLevel` config keys, the `SCRIPTORIUM_LOG_LEVEL` /
`SCRIPTORIUM_FILE_LOG_LEVEL` environment variable overrides, and the
`parseLogLevel` helper. Currently these have zero test coverage.

## What to do

In `tests/test_scriptorium.nim`, add a new suite `"log level config"` with
these tests:

1. **"loadConfig reads logLevel from scriptorium.json"** — write a config with
   `logLevel: "debug"`, load it, verify `cfg.logLevel == "debug"`.

2. **"loadConfig reads fileLogLevel from scriptorium.json"** — write a config
   with `fileLogLevel: "error"`, load it, verify `cfg.fileLogLevel == "error"`.

3. **"SCRIPTORIUM_LOG_LEVEL env overrides config logLevel"** — write a config
   with `logLevel: "error"`, set `SCRIPTORIUM_LOG_LEVEL=debug` via `putEnv`,
   load config, verify `cfg.logLevel == "debug"`. Use `defer` to restore the
   env var with `delEnv`.

4. **"SCRIPTORIUM_FILE_LOG_LEVEL env overrides config fileLogLevel"** — same
   pattern for the file log level env var.

5. **"logLevel defaults to empty when absent"** — load from a config without
   logLevel, verify `cfg.logLevel == ""`.

6. **"parseLogLevel parses valid levels"** — call `parseLogLevel` with
   `"debug"`, `"info"`, `"warn"`, `"warning"`, `"error"` and verify the
   correct `LogLevel` enum value for each. Note: `parseLogLevel` is in
   `src/scriptorium/orchestrator.nim` — you may need to import it or test it
   indirectly through `applyLogLevelFromConfig`.

7. **"parseLogLevel raises on invalid level"** — verify that an invalid string
   like `"verbose"` raises `ValueError`.

## Verification

Run `make test`. All new and existing tests must pass.

## Notes

- Use `putEnv` / `delEnv` from `std/os` for env var manipulation.
- If `parseLogLevel` is not exported, either export it (add `*`) or test the
  behavior through `applyLogLevelFromConfig` by checking `minLogLevel` from
  `src/scriptorium/logging.nim` after calling it.
- Use `jsony` for JSON serialization (already imported in test file).
