# Orchestrator Area — V4 Complete

**Area:** orchestrator
**Status:** done

## Summary

All orchestrator scope items through V4 are fully implemented and tested:

- **Run loop**: `scriptorium run` starts polling loop with idle sleep and error backoff.
- **MCP HTTP server**: Started in dedicated thread, endpoint from `endpoints.local` config (default `http://127.0.0.1:8097`).
- **Work gating**: Plan branch existence, healthy master (`make test` + `make integration-test`), runnable spec (not blank, not placeholder). Non-runnable spec logs `WAITING: no spec` message.
- **Tick order**: Architect → Manager → assign/execute ticket → process merge queue.
- **Master health cache**: In-memory cache keyed by HEAD commit. Persistent `health/cache.json` on plan branch (V4 §22).
- **Tick summary line (V3 §13)**: Single INFO-level line per tick with architect/manager/coding/merge status and ticket counts.
- **Session summary (V3 §16)**: Aggregate metrics logged on shutdown (signal or idle exit).
- **Signal handlers**: Graceful shutdown on SIGINT/SIGTERM.

Non-blocking tick with parallel agent execution (V5 §24) is scoped to the parallel-execution area.

## Prior Tickets

- 0027: Orchestrator baseline
- 0033: Tick summary line
- 0035: Session summary on shutdown
- 0043: Health cache persistence
