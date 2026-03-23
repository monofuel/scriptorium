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

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Single-module POSIX PID guard with JSON file I/O, defer-based cleanup, and 3-4 unit tests including a helper binary — moderate complexity but well-scoped with clear requirements, one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0085/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0085/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. The PID guard implementation is complete:

- **`acquirePidGuard`** - checks `.scriptorium/orchestrator.pid`, validates liveness via `posix.kill(Pid, 0)` with correct EPERM handling (treats EPERM as alive per spec §17, only ESRCH triggers stale takeover)
- **`releasePidGuard`** - deletes PID file on clean shutdown
- Both `runOrchestrator` and `runOrchestratorForTicks` call acquire/release with `defer`
- **4 tests**: PID file lifecycle, existence during run, live PID conflict (via helper binary), stale PID overwrite
- **Helper**: `tests/pid_guard_helper.nim` for the subprocess-based live PID test
```

### Agent Stdout Tail
```text
 only ESRCH triggers stale takeover)\n- **`releasePidGuard`** - deletes PID file on clean shutdown\n- Both `runOrchestrator` and `runOrchestratorForTicks` call acquire/release with `defer`\n- **4 tests**: PID file lifecycle, existence during run, live PID conflict (via helper binary), stale PID overwrite\n- **Helper**: `tests/pid_guard_helper.nim` for the subprocess-based live PID test","stop_reason":"end_turn","session_id":"f1e88156-4493-4ee5-9d3b-e528808e2735","total_cost_usd":2.0945385000000005,"usage":{"input_tokens":214,"cache_creation_input_tokens":71264,"cache_read_input_tokens":2620437,"output_tokens":13514,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":71264},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":214,"outputTokens":13514,"cacheReadInputTokens":2620437,"cacheCreationInputTokens":71264,"webSearchRequests":0,"costUSD":2.0945385000000005,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"6f7df77a-7d0d-46a8-ab79-a0325381fcab"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 33s

**Review Reasoning:** The implementation looks correct. Let me verify the `runOrchestrator` integration point.
Implementation is clean and complete. Key observations:

1. **EPERM handling is correct** — line 32: `if killRc == 0 or errno == EPERM` properly treats both "kill succeeded" and "permission denied" as "process alive", per spec §17.
2. **JSON format correct** — `PidFileContent` with `pid: int` and `timestamp: float`, serialized with jsony.
3. **Lifecycle correct** — `acquirePidGuard` called before loop, `releasePidGuard` via `defer` in both `runOrchestrator` and `runOrchestratorForTicks`.
4. **Tests cover all 4 scenarios**: creation+deletion, existence during run, live conflict, stale takeover.
5. **Helper binary** avoids stdout scanning — uses `quit(1)` exit code and stderr message, checked via `execCmdEx`.

One minor note: the `errno` check on line 32 should technically only be checked when `killRc != 0` (i.e., `killRc == 0` means alive regardless of errno). The current logic `killRc == 0 or errno == EPERM` works correctly because when `killRc == 0`, the `errno == EPERM` part is short-circuited. And when `killRc != 0`, `errno` is valid. So it's functionally correct.
Review submitted: **approved**. The implementation is correct, minimal, and covers all ticket requirements including the EPERM fix from the previous review's warning.

## Merge Queue Failure
- Summary: Implement orchestrator singleton PID guard per §17. Adds acquirePidGuard/releasePidGuard procs that write/check .scriptorium/orchestrator.pid with JSON {pid, timestamp} using jsony. Checks process liveness via posix.kill(Pid, 0) with correct EPERM handling (treats EPERM as alive, only ESRCH triggers stale takeover). Wired into both runOrchestrator and runOrchestratorForTicks with defer cleanup. Four tests: PID file lifecycle, existence during run, live PID conflict (via helper binary), and stale PID overwrite.\n
### Merge Output
```text
Auto-merging src/scriptorium/orchestrator.nim
CONFLICT (content): Merge conflict in src/scriptorium/orchestrator.nim
Auto-merging tests/test_orchestrator_flow.nim
Automatic merge failed; fix conflicts and then commit the result.
```

## Metrics
- wall_time_seconds: 3289
- coding_wall_seconds: 1873
- test_wall_seconds: 0
- attempt_count: 1
- outcome: reopened
- failure_reason: merge_conflict
- model: claude-opus-4-6
- stdout_bytes: 757266

## Post-Analysis
- actual_difficulty: hard
- prediction_accuracy: underestimated
- brief_summary: Predicted medium, actual was hard with 1 attempt(s) in 54m49s.

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 15
- reasoning: Merge conflict resolution in orchestrator.nim plus verifying existing PID guard implementation still works — single file conflict fix with test validation, one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0085/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0085/attempt-01.last_message.txt\n
### Agent Last Message
```text
Submitted. The PID guard implementation is already fully present in the codebase — the previous merge conflict was resolved and the code landed in master. All tests pass with no changes needed.
```

### Agent Stdout Tail
```text
_id":"299ea803-9d4a-4af6-9fae-9bc0a1315b2f","uuid":"c01bd3a0-8e9e-4984-b942-eb6e926e354e"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":470037,"duration_api_ms":63592,"num_turns":18,"result":"Submitted. The PID guard implementation is already fully present in the codebase — the previous merge conflict was resolved and the code landed in master. All tests pass with no changes needed.","stop_reason":"end_turn","session_id":"299ea803-9d4a-4af6-9fae-9bc0a1315b2f","total_cost_usd":0.458233,"usage":{"input_tokens":3607,"cache_creation_input_tokens":37456,"cache_read_input_tokens":278996,"output_tokens":2664,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":37456},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":3607,"outputTokens":2664,"cacheReadInputTokens":278996,"cacheCreationInputTokens":37456,"webSearchRequests":0,"costUSD":0.458233,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"dc163d81-945d-43f1-bf0e-f868d162e196"}
```
