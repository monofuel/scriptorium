# Config, Logging, Tests, And CI Baseline

Covers runtime configuration, log level handling, test commands, CI workflows, and project structure opinions.

## Scope

- Runtime config file: `scriptorium.json`.
- Supported config keys:
  - `agents.architect.{harness, model, reasoningEffort}`
  - `agents.coding.{harness, model, reasoningEffort}`
  - `agents.manager.{harness, model, reasoningEffort}`
  - `agents.reviewer.{harness, model, reasoningEffort}`
  - `endpoints.local`
  - `logLevel`
  - `concurrency.maxAgents` (V5, integer, default 1)
  - `concurrency.tokenBudgetMB` (V5, optional integer megabytes)
  - `agents.coding.progressTimeout` (V8, integer minutes, default 10)
  - `discord.{enabled, serverId, channelId, allowedUserIds}` (V12)
  - `mattermost.{enabled, url, channelId, allowedUserIds}` (V12)
- `SCRIPTORIUM_LOG_LEVEL` environment variable overrides config-file `logLevel`.

**Project opinions (V11, §35):**
- Required make targets for all managed projects:
  - `make build` — compile the project, must exit 0 on success, run before tests.
  - `make test` — unit tests, fast, no network access, no API keys, run on every commit and before every merge.
  - `make integration-test` — tests hitting real services, may require credentials, run on default branch pushes.
  - `make e2e-test` — (optional) full end-to-end smoke tests, run on default branch pushes if present.

**Repository test commands:**
- `make test` runs `tests/test_*.nim`.
- `make integration-test` runs `tests/integration_*.nim`.
- `make e2e-test` runs end-to-end coverage.

**CI baseline:**
- Build workflow: unit tests on push and PR, linux binary build on push.
- Integration workflow: default branch push and `workflow_dispatch`.
- E2E workflow: default branch push and `workflow_dispatch`.

**E2E test uses `scriptorium init` (V11, §44):**
- The existing e2e test (Euler test) must use `scriptorium init` instead of manually seeding `AGENTS.md` and Makefile.
- Remove manual file creation from test setup; run `scriptorium init` (via `runInit`) on the temp repo.
- Verify `AGENTS.md`, Makefile, and `scriptorium.json` were created by init.
- Continue with existing flow: write spec, start orchestrator, verify ticket completion and `make test` passing.
- Proves init produces a repo the orchestrator can run against without manual scaffolding.

## Spec References

- Section 9: Config, Logging, Tests, And CI Baseline.
- Section 24: Concurrent Agent Execution (V5, concurrency config).
- Section 26: Resource Management (V5, token budget config).
- Section 34: Agent Crash Recovery (V8, progress timeout config).
- Section 35: Project Opinions (V11, make target requirements).
- Section 44: E2E Test Uses `scriptorium init` (V11).
- Section 45: Discord Bot config (V12).
- Section 46: Mattermost Bot config (V12).
