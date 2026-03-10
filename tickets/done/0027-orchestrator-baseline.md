# Orchestrator Run Loop Baseline

**Area:** orchestrator
**Status:** done

## Summary

The `scriptorium run` polling loop, gating logic, and tick ordering are fully implemented and tested.

## What Exists

- `scriptorium run` starts the orchestrator polling loop, MCP HTTP server, and repository-backed logging.
- MCP endpoint from `scriptorium.json` `endpoints.local`, defaulting to `http://127.0.0.1:8097`.
- Continuous polling with 200ms idle sleep between ticks.
- Work gated by:
  - Existence of `scriptorium/plan` branch.
  - Healthy `master` (required quality targets `make test` and `make integration-test` pass in order on a `master` worktree).
  - Runnable `spec.md` (not blank, not the init placeholder).
- Non-runnable spec logs: `WAITING: no spec — run 'scriptorium plan'`.
- Tick order:
  1. Architect area generation when areas are missing.
  2. Manager ticket generation for areas without open or in-progress tickets.
  3. Assign and execute the oldest open ticket.
  4. Process at most one merge-queue item.
- `master` health cached by `master` HEAD commit, recomputed only when `master` changes.
- Signal handlers installed for graceful shutdown.
- Tests: `test_scriptorium.nim`, `integration_orchestrator_live_submit_pr.nim`.
