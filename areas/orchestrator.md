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
  3. Assign and execute open tickets (parallel when concurrency > 1, see parallel-execution area).
  4. Process at most one merge-queue item.
- Tick must not block on a single agent completing when running in parallel mode — check for completable agents, start new agents, and continue other tick phases (V5, §24, detail in parallel-execution area).
- `master` health cached by `master` HEAD commit, recomputed only when `master` changes.
- `master` health cache persisted to `health/cache.json` on the plan branch for cross-session persistence (V4, §22, see health-cache area).
- Tick summary line: at the end of each tick, log a single INFO-level summary capturing full system state (see observability area).
- Session summary: on shutdown (signal or idle exit), log aggregate session metrics (see observability area).

**Module split (V7, §27):**
- `orchestrator.nim` must be decomposed into focused modules, each covering a single responsibility.
- Target modules: `git_ops.nim`, `lock_management.nim`, `ticket_metadata.nim`, `prompt_builders.nim`, `output_formatting.nim`, `ticket_analysis.nim`, `merge_queue.nim`, `coding_agent.nim`, `architect_agent.nim`, `manager_agent.nim`, `ticket_assignment.nim`, `health_checks.nim`, `mcp_server.nim`, `shared_state.nim`, `interactive_sessions.nim`.
- `orchestrator.nim` retains only the main loop, signal handlers, and `runOrchestrator` entry points.
- Extraction order: bottom-up, starting with modules that have no internal dependencies (`git_ops`, `lock_management`, `ticket_metadata`), then upward through dependents.
- Each extraction is a single commit that moves procs and updates imports.
- All existing tests must pass after each extraction — no behavior changes permitted.
- Focused unit tests should be added for newly isolated modules where coverage is thin.

**SIGSEGV shutdown fix (V7, §28):**
- The orchestrator must shut down cleanly without triggering SIGSEGV in mummy's allocator.
- Root cause: calling `httpServer.close()` from the main thread while mummy's `serve()` is running on the server thread causes a use-after-free.
- Fix: coordinate shutdown so the server thread closes itself rather than receiving a cross-thread close.
  - Main thread sets a shutdown flag (atomic or shared-memory signal).
  - Server thread checks the shutdown flag and calls `close()` on itself.
  - Main thread calls `joinThread()` only after the server thread has exited.
- No sleep-based workarounds — shutdown must be event-driven.
- If mummy does not support flag-based shutdown, investigate newer mummy versions or alternative HTTP server libraries.

## Spec References

- Section 3: Orchestrator Run Loop.
- Section 13: Tick Summary Line (V3, detail in observability area).
- Section 16: Session Summary On Shutdown (V3, detail in observability area).
- Section 22: Commit Health Cache (V4, detail in health-cache area).
- Sections 23-24: Parallel Ticket Assignment and Concurrent Agent Execution (V5, detail in parallel-execution area).
- Section 27: Orchestrator Module Split (V7).
- Section 28: SIGSEGV Shutdown Fix (V7).
