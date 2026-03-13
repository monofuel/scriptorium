# Orchestrator Run Loop

Covers the `scriptorium run` main polling loop, gating logic, and tick ordering.

## Scope

- `scriptorium run` starts the orchestrator polling loop, MCP HTTP server, and repository-backed logging.
- MCP endpoint from `scriptorium.json` `endpoints.local`, defaulting to `http://127.0.0.1:8097`.
- Continuous polling with idle sleep between ticks.
- Work gated by:
  - Existence of `scriptorium/plan` branch.
  - Healthy `master` (required quality targets `make test` and `make integration-test` pass in order on a `master` worktree).
  - Runnable `spec.md` (not blank, not the init placeholder).
- Non-runnable spec logs: `WAITING: no spec — run 'scriptorium plan'`.
- Tick order:
  1. Architect area generation (content-hash driven, see agent-execution area).
  2. Manager ticket generation for eligible areas (content-hash driven, see agent-execution area).
  3. Assign and execute the oldest open ticket.
  4. Process at most one merge-queue item.
- `master` health cached by `master` HEAD commit, recomputed only when `master` changes.
- `master` health cache persisted to `health/cache.json` on the plan branch for cross-session persistence (V4, §22, see health-cache area).
- Tick summary line: at the end of each tick, log a single INFO-level summary capturing full system state (see observability area).
- Session summary: on shutdown (signal or idle exit), log aggregate session metrics (see observability area).

## Spec References

- Section 3: Orchestrator Run Loop.
- Section 13: Tick Summary Line (V3, detail in observability area).
- Section 16: Session Summary On Shutdown (V3, detail in observability area).
- Section 22: Commit Health Cache (V4, detail in health-cache area).
