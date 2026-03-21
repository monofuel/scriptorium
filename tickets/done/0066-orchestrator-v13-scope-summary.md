# Orchestrator Run Loop — V13 Scope Summary

**Area:** orchestrator

All orchestrator scope items through V4 are fully implemented:

- **`scriptorium run`**: Starts polling loop, MCP HTTP server, and repository-backed logging.
- **MCP endpoint**: From `scriptorium.json` `endpoints.local`, default `http://127.0.0.1:8097`.
- **Work gating**: Plan branch existence, healthy master (test + integration-test), runnable spec.
- **Non-runnable spec log**: `WAITING: no spec — run 'scriptorium plan'`.
- **Master health cache**: Persisted to `health/cache.json` on plan branch (V4 §22), keyed by HEAD commit.
- **Tick summary line**: Single INFO-level line at end of each tick with full system state (V3 §13).
- **Session summary**: Aggregate metrics logged on shutdown (V3 §16).
- **Parallel agent execution**: Non-blocking tick with agent pool, concurrent coding agents in isolated worktrees (V5 §24).
- **Resource management**: Token budget enforcement and rate limit backpressure (V5 §26).

The V13 restructured tick order (§30) and narrow plan branch locking (§31) require the per-area concurrent manager model and shared agent pool, which are tracked in the parallel-execution area. Once those features are implemented, the orchestrator tick will be updated to interleave managers and coders and use narrow locking.
