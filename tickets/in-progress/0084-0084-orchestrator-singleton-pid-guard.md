# 0084 — Orchestrator Singleton PID Guard

**Area:** plan-locking
**File:** `tickets/0084-orchestrator-pid-guard.md`

## Summary

Implement the orchestrator singleton PID guard that prevents two orchestrator instances from running against the same repo simultaneously.

## Requirements

1. On `scriptorium run` startup (in `runOrchestrator` in `src/scriptorium/orchestrator.nim`), write `.scriptorium/orchestrator.pid` containing a JSON object: `{"pid": <pid>, "timestamp": <unix_epoch>}`.
2. If the file already exists on startup:
   - Read the PID and check liveness with `posix.kill(Pid(pid), 0)`.
   - If PID is alive: abort with a clear error message (e.g., "Another orchestrator is already running (PID <pid>, started <timestamp>)").
   - If PID is dead: log a warning ("Stale orchestrator PID file found for dead PID <pid>, overwriting"), overwrite the PID file, and proceed.
3. On clean shutdown, delete the PID file. Use `defer` after writing the file to ensure cleanup.
4. The PID file path is `<repoPath>/.scriptorium/orchestrator.pid`.

## Implementation Notes

- Add a new proc (e.g., `acquireOrchestratorPidGuard` and `releaseOrchestratorPidGuard`) in `src/scriptorium/lock_management.nim`.
- Use `jsony` for JSON serialization (project dependency per AGENTS.md).
- Call the guard from `runOrchestrator` in `src/scriptorium/orchestrator.nim` before starting the HTTP server.
- Also call from `runOrchestratorForTicks` so tests that use bounded loops also get guarded.
- Use `posix.kill(Pid(pid), 0)` for liveness check, same pattern as existing `lockPathIsStale`.
- Ensure `.scriptorium/` directory exists before writing (use `createDir`).
- This is a one-time startup check only, not checked during operation.

## Testing

- Add unit tests in `tests/test_lock_management.nim` (new file):
  - Test writing and reading the PID file.
  - Test that a stale PID file (from a dead process) is overwritten.
  - Test that a live PID file (current process) causes an error.
  - Test cleanup on release.
````

---

````markdown
# 0085 — Replace Directory-Based Lock with File-Based Commit Lock

**Area:** plan-locking
**File:** `tickets/0085-file-based-commit-lock.md`
**Depends:** 0084

## Summary

Replace the current directory-based repo lock (`mkdir` + `pid` file inside a directory) with the spec-required file-based transactional commit lock at `.scriptorium/commit.lock`.

## Requirements

1. Lock file path: `.scriptorium/commit.lock` (a regular file, not a directory).
2. On acquisition, write a JSON object: `{"pid": <pid>, "timestamp": <unix_epoch>}` where timestamp is `epochTime()` (float seconds).
3. On release, delete the file.
4. Use atomic file creation to detect contention: write to a temp file then `moveFile` or use `O_CREAT | O_EXCL` via posix `open()` to fail if the file exists.
5. Remove the old directory-based locking code: `tryAcquireRepoLock` (mkdir-based), `lockHolderPid`, `lockPathIsStale`, `withRepoLock` — all replaced by new implementations.
6. Remove constants `ManagedRepoLockName`, `ManagedRepoLockPidFileName`, `ManagedLockDirName` from `git_ops.nim` and `managedRepoLockPath` proc.
7. Add new constant `CommitLockFileName = "commit.lock"` in `git_ops.nim`.

## Implementation Notes

- Modify `src/scriptorium/lock_management.nim`.
- Use `jsony` for JSON serialization/deserialization of the lock file content.
- Use `posix.open(path, O_CREAT or O_EXCL or O_WRONLY, 0o644)` for atomic file creation to detect if lock already exists.
- The new `acquireCommitLock` proc should return a handle/path that `releaseCommitLock` uses to delete.
- Update `withRepoLock` (or rename to `withCommitLock`) to use the new mechanism.
- Update `withLockedPlanWorktree` to use the new lock.
- Ensure all existing callers of `withRepoLock` / `withLockedPlanWorktree` continue to work unchanged.

## Testing

- Update/create tests in `tests/test_lock_management.nim`:
  - Test that lock file is created with correct JSON content.
  - Test that concurrent acquisition is detected (file already exists).
  - Test that release deletes the file.
````

---

````markdown
# 0086 — Commit Lock Retry and Staleness Logic

**Area:** plan-locking
**File:** `tickets/0086-commit-lock-retry-staleness.md`
**Depends:** 0085

## Summary

Add retry-with-backoff and staleness detection to the transactional commit lock, per the spec's contention handling requirements.

## Requirements

1. **Fresh lock (< 30 seconds old):** Wait 100ms and retry, up to 50 retries (5 seconds max wait).
2. **Stale lock (>= 30 seconds old):** Log a warning ("stealing stale commit lock from PID <pid>, held for <duration>s"), delete the file, and acquire.
3. **All retries exhausted:** Fail with a clear error message ("Failed to acquire commit lock after 5 seconds; held by PID <pid>").
4. Staleness threshold constant: `CommitLockStalenessSeconds = 30`.
5. Retry interval: 100ms. Max retries: 50.

## Implementation Notes

- Modify the `acquireCommitLock` proc in `src/scriptorium/lock_management.nim`.
- On contention (file exists), read the JSON to get PID and timestamp.
- Calculate age: `epochTime() - timestamp`.
- If age >= 30s, steal the lock (delete file, re-acquire).
- If age < 30s, `sleep(100)` and retry.
- Use `jsony` to parse the lock file JSON. Handle corrupt/unreadable lock files by treating them as stale.
- Use `os.sleep(100)` for the retry delay.
- Use `logging` module's `logWarn` for the stale lock warning.

## Testing

- Add tests in `tests/test_lock_management.nim`:
  - Test that a stale lock (timestamp > 30s ago) is stolen with a warning.
  - Test that a fresh lock causes retries (mock by creating a lock file with current timestamp, then removing it after a short delay in a thread).
  - Test that exhausted retries raise an error.
  - Test that a corrupt lock file is treated as stale and stolen.
````

---

````markdown
# 0087 — Clean Up Legacy Lock Constants and Paths

**Area:** plan-locking
**File:** `tickets/0087-cleanup-legacy-lock-paths.md`
**Depends:** 0085

## Summary

Remove unused legacy lock directory infrastructure after the switch to file-based commit lock, and ensure the new lock path is used consistently.

## Requirements

1. Remove from `src/scriptorium/git_ops.nim`:
   - `ManagedLockDirName` constant (currently `"locks"`).
   - `ManagedRepoLockName` constant (currently `"repo.lock"`).
   - `ManagedRepoLockPidFileName` constant (currently `"pid"`).
   - `managedRepoLockPath` proc.
2. Add to `src/scriptorium/git_ops.nim`:
   - `CommitLockFileName* = "commit.lock"`
   - `OrchestratorPidFileName* = "orchestrator.pid"`
   - `proc commitLockPath*(repoPath: string): string` returning `<repoPath>/.scriptorium/commit.lock`.
   - `proc orchestratorPidPath*(repoPath: string): string` returning `<repoPath>/.scriptorium/orchestrator.pid`.
3. Update all imports and references in `lock_management.nim` to use the new path procs.
4. Verify no other files reference the removed constants (grep and fix any remaining references).

## Testing

- `make test` passes with no references to removed constants.
- Existing lock management tests pass with new paths.
````

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0084-0084-orchestrator-singleton-pid-guard

## Prediction
- predicted_difficulty: hard
- predicted_duration_minutes: 30
- reasoning: Four interconnected tickets spanning lock_management.nim, git_ops.nim, and orchestrator.nim with POSIX process liveness checks, atomic file operations, retry/backoff logic, legacy code removal, and comprehensive test coverage — high integration risk across modules likely requiring 2+ attempts.

## Prediction
- predicted_difficulty: hard
- predicted_duration_minutes: 30
- reasoning: Four linked tickets touching lock_management.nim, git_ops.nim, and orchestrator.nim with POSIX liveness checks, atomic file ops, retry/backoff, legacy removal, and new test file — cross-module integration risk likely requires 2+ attempts.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0084/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0084/attempt-01.last_message.txt\n
### Agent Last Message
```text
All done. Here's a summary of the changes:

**`src/scriptorium/git_ops.nim`** — Added `OrchestratorPidFileName` constant and `orchestratorPidPath` proc.

**`src/scriptorium/lock_management.nim`** — Added `OrchestratorPidFile` type and two procs:
- `acquireOrchestratorPidGuard` — writes PID file, checks liveness if one exists (abort if alive, warn+overwrite if dead)
- `releaseOrchestratorPidGuard` — deletes the PID file on shutdown

**`src/scriptorium/orchestrator.nim`** — Called the guard from both `runOrchestrator` and `runOrchestratorForTicks` with `defer` cleanup.

**`tests/test_lock_management.nim`** — 5 unit tests covering write, release/cleanup, stale PID overwrite, live PID rejection, and directory auto-creation.
```

### Agent Stdout Tail
```text
rite if dead)\n- `releaseOrchestratorPidGuard` — deletes the PID file on shutdown\n\n**`src/scriptorium/orchestrator.nim`** — Called the guard from both `runOrchestrator` and `runOrchestratorForTicks` with `defer` cleanup.\n\n**`tests/test_lock_management.nim`** — 5 unit tests covering write, release/cleanup, stale PID overwrite, live PID rejection, and directory auto-creation.","stop_reason":"end_turn","session_id":"74423eb8-9239-4226-828f-a9649ac831cc","total_cost_usd":1.2131615000000002,"usage":{"input_tokens":12768,"cache_creation_input_tokens":54382,"cache_read_input_tokens":1193018,"output_tokens":8517,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":54382},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":12768,"outputTokens":8517,"cacheReadInputTokens":1193018,"cacheCreationInputTokens":54382,"webSearchRequests":0,"costUSD":1.2131615000000002,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"717b7259-6a82-4524-9aa4-23a78d71d7f8"}
```
