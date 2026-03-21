# Config, Logging, Tests, And CI Baseline

Covers runtime configuration, log level handling, test commands, and CI workflows.

## Scope

- Runtime config file: `scriptorium.json`.
- Supported config keys:
  - `agents.architect.{harness, model, reasoningEffort}`
  - `agents.coding.{harness, model, reasoningEffort}`
  - `agents.manager.{harness, model, reasoningEffort}`
  - `agents.reviewer.{harness, model, reasoningEffort}`
  - `endpoints.local`
  - `logLevel`
  - `concurrency.maxAgents` (V5/V13, integer, default 4 — changed from 1 in V13)
  - `concurrency.tokenBudgetMB` (V5, optional integer megabytes)
- `SCRIPTORIUM_LOG_LEVEL` environment variable overrides config-file `logLevel`.
- Repository test commands:
  - `make test` runs `tests/test_*.nim`.
  - `make integration-test` runs `tests/integration_*.nim`.
  - `make e2e-test` runs end-to-end coverage.
- CI baseline:
  - Build workflow: unit tests on push and PR, linux binary build on push.
  - Integration workflow: `master` push and `workflow_dispatch`.
  - E2E workflow: `master` push and `workflow_dispatch`.

## Spec References

- Section 9: Config, Logging, Tests, And CI Baseline.
- Section 24: Concurrent Agent Execution (V5, concurrency config).
- Section 26: Resource Management (V5, token budget config).
- Section 27: Default maxAgents Changed To 4 (V13).
