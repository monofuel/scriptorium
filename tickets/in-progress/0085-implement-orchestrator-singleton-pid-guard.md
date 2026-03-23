# Implement Orchestrator Singleton PID Guard

**Area:** orchestrator

## Problem

The spec (§17) requires an orchestrator singleton PID guard to prevent multiple `scriptorium run` instances from operating on the same repository simultaneously. The area doc references it as part of `scriptorium run` startup, but it is not implemented — there is no code referencing `.scriptorium/orchestrator.pid` anywhere in the source.

## Requirements

Implement the PID guard in `src/scriptorium/orchestrator.nim` (or a helper module) with the following behavior:

### On startup (`runOrchestrator`), before the polling loop:
1. Check for `.scriptorium/orchestrator.pid` in the repo root.
2. If the file exists, read the PID from it and check liveness with `posix.kill(Pid(pid), 0)`:
   - If the PID is alive (kill returns 0): abort with a clear error message like `"ERROR: orchestrator already running (PID <pid>)"` and `quit(1)`.
   - If the PID is dead (kill fails with ESRCH): log a warning `"orchestrator PID file exists but process <pid> is dead, taking over"`, overwrite the file, and proceed.
3. If the file does not exist, write it.
4. The file content should be a JSON object: `{"pid": <current_pid>, "timestamp": <unix_epoch_float>}`.
5. Use `jsony` for JSON serialization (project standard per AGENTS.md dependencies).

### On clean shutdown:
- Delete `.scriptorium/orchestrator.pid`. This should happen in `runOrchestrator` (or `runOrchestratorLoop`) after the loop exits, as part of cleanup.
- Use a `defer` or ensure it runs even on signal-based shutdown.

### Additional constraints (from spec):
- This is a one-time startup check, not re-checked during operation.
- Does not work across container boundaries (different PID namespaces) — this is a known limitation, no special handling needed.
- The `preflightValidation` proc already runs before the loop and is a natural place for the guard, OR it can be a separate proc called from `runOrchestrator`.

### Tests:
- Add a unit test in the appropriate test file verifying:
  - PID file is created on startup.
  - PID file is deleted on clean shutdown.
  - A second invocation with a live PID file aborts.
  - A stale PID file (dead process) is overwritten with a warning.

## Files likely affected
- `src/scriptorium/orchestrator.nim` — add PID guard logic to `runOrchestrator` startup/shutdown.
- `tests/test_orchestrator_flow.nim` — add PID guard tests.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0085-implement-orchestrator-singleton-pid-guard
