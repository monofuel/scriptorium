# Plan Branch Locking

Two mechanisms protect plan branch state: the orchestrator singleton PID guard and the transactional commit lock.

## Scope

**Orchestrator Singleton PID Guard:**
- On `scriptorium run` startup, write `.scriptorium/orchestrator.pid` containing the process PID and a startup timestamp.
- If the file already exists, read the PID and check liveness with `kill(pid, 0)`:
  - PID alive: abort with a clear error message.
  - PID dead: log a warning, overwrite the PID file, proceed.
- On clean shutdown, delete the PID file.
- One-time startup check only, not checked during operation.
- Does not work across container boundaries (different PID namespaces). Constraint: scriptorium runs either always in a container or always on the host for a given repo, never both simultaneously.

**Transactional Commit Lock:**
- Short-lived file lock held only for read-modify-commit cycles on the plan branch.
- Contract:
  - Acquired immediately before a plan branch write operation.
  - Lock holder reads state, modifies files, runs `git commit`, then releases.
  - Never held during agent execution, API calls, test runs, or anything beyond a few seconds.
  - Maximum expected hold time: < 2 seconds (`git add` + `git commit`).
- Implementation:
  - Lock file: `.scriptorium/commit.lock` (a regular file, not a directory).
  - On acquisition, write a JSON object: `{"pid": <pid>, "timestamp": <unix_epoch>}`.
  - On release, delete the file.
  - Staleness threshold: 30 seconds.
- Contention handling:
  - Fresh lock (< 30s old): wait 100ms and retry, up to 50 retries (5 seconds max wait).
  - Stale lock (>= 30s old): log warning ("stealing stale commit lock from PID <pid>, held for <duration>"), delete and acquire.
  - All retries exhausted: fail with a clear error.
- Callers:
  - Orchestrator: architect area writes, manager ticket writes, area hash updates, ticket state transitions, merge queue operations, health cache writes.
  - `scriptorium plan`: spec.md commits at the end of each interactive turn or one-shot invocation.
  - All callers are brief git commit operations.
- Worktree management is separate: `ensurePlanWorktree()` runs without locking (idempotent, atomic git worktree operations). Only the subsequent commit operation acquires the commit lock.

**Lock Hold Patterns:**
- Reading areas: brief commit lock to snapshot area content at start of tick. Done once for all areas.
- Agent execution: no lock needed. Manager agents run in threads and produce ticket content in memory.
- Writing tickets: main thread acquires commit lock per completed manager, writes, commits, releases. Each completed manager's write is a separate lock acquisition.
- Architect holds commit lock for its full duration (sequential, runs before managers).

## Spec References

- Section 17: Plan Branch Locking.
- Section 3: Orchestrator Run Loop (PID guard on startup).
- Section 2: Planning And Ask Sessions (commit lock for plan commits).
