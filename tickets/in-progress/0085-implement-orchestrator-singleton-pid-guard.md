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

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Single-module change with POSIX process checking, JSON file I/O, and cleanup logic plus 4 unit tests — moderate complexity but well-scoped with clear requirements, one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 2\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0085/attempt-02.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0085/attempt-02.last_message.txt\n
### Agent Last Message
```text
Done. The PID guard implementation is complete:

- **`acquirePidGuard`** - checks `.scriptorium/orchestrator.pid`, validates liveness via `posix.kill(Pid, 0)`, aborts if alive, takes over if stale, writes JSON with `{pid, timestamp}`
- **`releasePidGuard`** - deletes PID file on clean shutdown
- Both `runOrchestrator` and `runOrchestratorForTicks` call acquire/release with `defer`
- **3 tests**: PID file lifecycle, live PID conflict (via helper binary), stale PID overwrite
- **Helper**: `tests/test_pid_guard_helper.nim` for the subprocess-based live PID test
```

### Agent Stdout Tail
```text
aborts if alive, takes over if stale, writes JSON with `{pid, timestamp}`\n- **`releasePidGuard`** - deletes PID file on clean shutdown\n- Both `runOrchestrator` and `runOrchestratorForTicks` call acquire/release with `defer`\n- **3 tests**: PID file lifecycle, live PID conflict (via helper binary), stale PID overwrite\n- **Helper**: `tests/test_pid_guard_helper.nim` for the subprocess-based live PID test","stop_reason":"end_turn","session_id":"4d60d226-d6d6-40ef-9ed6-f5e955a22278","total_cost_usd":0.49847725,"usage":{"input_tokens":132,"cache_creation_input_tokens":43469,"cache_read_input_tokens":355922,"output_tokens":1927,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":43469},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":132,"outputTokens":1927,"cacheReadInputTokens":355922,"cacheCreationInputTokens":43469,"webSearchRequests":0,"costUSD":0.49847725,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"89c38116-5484-4271-95c4-7149a7211e58"}
```

## Review
**Review:** approved with warnings
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 1m4s

**Warnings:** Implementation is correct and well-structured. One minor spec deviation: `acquirePidGuard` checks `killRc == 0` vs non-zero, but does not differentiate `EPERM` (process alive, different user) from `ESRCH` (process dead). Per §17, only `ESRCH` should trigger the stale takeover path; `EPERM` means the process exists. In practice this is unlikely to matter (same user running scriptorium on a given repo), but for strict spec compliance, the else branch should check `errno == ESRCH` and treat `EPERM` as alive.

**Review Reasoning:** Let me read the relevant source files for full context.
I've reviewed the implementation. Let me verify one more detail about the signal handler and shutdown path.
The implementation is clean and correct. Here's my assessment:

**Correct:**
- `acquirePidGuard`/`releasePidGuard` procs with proper lifecycle
- JSON format with `pid` + `timestamp` using `jsony`
- `defer` ensures cleanup on both normal exit and signal shutdown (signal sets `shouldRun = false` → loop exits → defer runs)
- Called from both `runOrchestrator` and `runOrchestratorForTicks`
- All 4 test scenarios covered (create, delete, live abort, stale takeover)
- Helper binary approach for the live-PID test is clever and avoids stdout scanning
- Follows Nim conventions (imports, doc comments, variable naming)

**Minor concern:** `acquirePidGuard` treats any non-zero `kill` return as "dead process", but `kill` returning -1 with `errno == EPERM` means the process IS alive (just owned by a different user). The spec says "kill fails with ESRCH" for the dead case. In practice this is unlikely to matter (same user, same repo), but it's a slight deviation from spec §17.
**Review: Approved with warnings**

The PID guard implementation is solid. One minor deviation from spec §17: the `EPERM` errno case (process alive but owned by different user) is treated as "dead" instead of "alive." This is unlikely to matter in practice but worth noting for strict spec compliance.
