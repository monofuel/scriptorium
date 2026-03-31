# Orchestrator Run Loop

Covers the `scriptorium run` main polling loop, gating logic, tick ordering, default branch resolution, and pre-flight validation.

## Scope

- `scriptorium run` starts the orchestrator polling loop, MCP HTTP server, and repository-backed logging.
- MCP endpoint from `scriptorium.json` `endpoints.local`, defaulting to `http://127.0.0.1:8097`.
- Continuous polling with idle sleep between ticks.

**Default branch detection (V11, §36):**
- The orchestrator must not hardcode `master` or `main`. It must resolve the default branch dynamically.
- Resolution order:
  1. Check `refs/remotes/origin/HEAD` — if set, use that.
  2. If not set, probe for common names (`master`, `main`, `develop`) and use whichever exists locally.
  3. During `scriptorium init`, once resolved, run `git remote set-head origin <branch>` so future runs skip the probe.
  4. If nothing works, error with a clear message asking the user to set the default branch.
- All hardcoded `master` references in the orchestrator, merge queue, and init code must be replaced with the resolved default branch.

**Pre-flight validation (V11, §41):**
- Before launching the polling loop, `scriptorium run` must perform upfront validation with clear, actionable error messages:
  - `scriptorium/plan` branch exists (already done).
  - `AGENTS.md` exists on the default branch — warn if missing.
  - Makefile exists on the default branch — error if missing (orchestrator cannot function without quality gates).
  - `make test` and `make integration-test` targets exist (dry-run via `make -n`) — warn if either fails.
  - Agent binary is available (`codex`, `claude`, or `typoi` depending on configured harness) — error if missing.
  - Agent auth is available (API keys or OAuth credentials for configured harness) — error if missing.
- Error messages must suggest corrective action (e.g., `Error: Makefile not found. Run 'scriptorium init' or create a Makefile with 'test' and 'integration-test' targets.`).

**Work gating:**
- Work gated by:
  - Existence of `scriptorium/plan` branch.
  - Healthy default branch (required quality targets `make test` and `make integration-test` pass in order on a default-branch worktree).
  - Runnable `spec.md` (not blank, not the init placeholder).
- Non-runnable spec logs: `WAITING: no spec — run 'scriptorium plan'`.

**Tick order:**
1. Architect area generation (content-hash driven, see agent-execution area).
2. Manager ticket generation for eligible areas (content-hash driven, see agent-execution area).
3. Assign and execute open tickets (parallel when concurrency > 1, see parallel-execution area).
4. Process at most one merge-queue item.

- Tick must not block on a single agent completing when running in parallel mode — check for completable agents, start new agents, and continue other tick phases (V5, §24, detail in parallel-execution area).
- Default-branch health cached by HEAD commit, recomputed only when HEAD changes.
- Default-branch health cache persisted to `health/cache.json` on the plan branch for cross-session persistence (V4, §22, see health-cache area).
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

**Startup recovery sequence (V8, §31):**
- On orchestrator start, before the first tick, run `recoverFromCrash` to detect and reconcile stale state from a previous crash or unclean shutdown.
- Recovery steps: clean orphaned worktrees, detect stale agent processes, reconcile dirty plan branch (via journal replay if applicable), validate merge queue vs default-branch HEAD, log recovery summary.
- Detail in crash-recovery area.

## Spec References

- Section 3: Orchestrator Run Loop.
- Section 13: Tick Summary Line (V3, detail in observability area).
- Section 16: Session Summary On Shutdown (V3, detail in observability area).
- Section 22: Commit Health Cache (V4, detail in health-cache area).
- Sections 23-24: Parallel Ticket Assignment and Concurrent Agent Execution (V5, detail in parallel-execution area).
- Section 27: Orchestrator Module Split (V7).
- Section 28: SIGSEGV Shutdown Fix (V7).
- Section 31: Startup Recovery Sequence (V8, detail in crash-recovery area).
- Section 36: Default Branch Detection (V11).
- Section 41: Pre-Flight Validation In `scriptorium run` (V11).
