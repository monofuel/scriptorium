# Config, Logging, Tests, And CI Baseline

**Area:** config-testing
**Status:** done

## Summary

Runtime configuration, log level handling, test commands, and CI workflows are fully implemented.

## What Exists

- `scriptorium.json` runtime config file parsed in `config.nim`.
- Supported config keys:
  - `agents.architect.{harness, model, reasoningEffort}`
  - `agents.coding.{harness, model, reasoningEffort}`
  - `agents.manager.{harness, model, reasoningEffort}`
  - `endpoints.local` (defaults to `http://127.0.0.1:8097`)
  - `logLevel`
- `SCRIPTORIUM_LOG_LEVEL` environment variable overrides config-file `logLevel`.
- `logging.nim`: structured logger with debug/info/warn/error levels, stdout and file output.
- Makefile test targets: `make test` runs `tests/test_*.nim`; `make integration-test` runs `tests/integration_*.nim`; `make e2e-test` runs end-to-end tests.
- CI workflows in `.github/workflows/`:
  - `build.yml`: runs unit tests on push and PR; builds linux binary on push.
  - `integration.yml`: runs on `master` push and `workflow_dispatch`.
  - `e2e.yml`: runs on `master` push and `workflow_dispatch`.
