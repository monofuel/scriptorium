# Config, Logging, Tests, And CI — Baseline Complete

**Area:** config-testing

All config-testing scope items are implemented except the V13 maxAgents default change (ticket 0064):

- **Runtime config**: `scriptorium.json` parsed with all supported keys.
- **Agent configs**: `agents.architect`, `agents.coding`, `agents.manager`, `agents.reviewer` each with `harness`, `model`, `reasoningEffort`.
- **Endpoints**: `endpoints.local` with default `http://127.0.0.1:8097`.
- **Log level**: `logLevel` config key with `SCRIPTORIUM_LOG_LEVEL` env override.
- **Concurrency**: `concurrency.maxAgents` and `concurrency.tokenBudgetMB` parsed and used.
- **Test commands**: `make test`, `make integration-test`, `make e2e-test` all functional.
- **CI workflows**: `build.yml` (unit tests on push/PR, binary build), `integration.yml` (master push + dispatch), `e2e.yml` (master push + dispatch).
- **Unit test coverage**: Config defaults, agent config parsing, concurrency config, timeout config, rate limit backoff.
