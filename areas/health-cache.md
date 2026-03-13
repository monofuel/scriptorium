Commit Health Cache

V4 feature: persistent `master` health check cache on the plan branch that survives container restarts and session boundaries.

Scope:

**Cache location and structure:**
- Cache file: `health/cache.json` on the `scriptorium/plan` branch.
- JSON object mapping commit hashes to result records:
  - `healthy`: boolean.
  - `timestamp`: ISO 8601 timestamp.
  - `test_exit_code`: integer.
  - `integration_test_exit_code`: integer.
  - `test_wall_seconds`: integer.
  - `integration_test_wall_seconds`: integer.

**Cache lookup and write flow:**
- On startup or after a merge changes `master` HEAD, the orchestrator must:
  1. Look up the current `master` HEAD commit in `health/cache.json`.
  2. If found and healthy: skip the health check entirely, log `master health: cached healthy for <commit-hash>`.
  3. If found and unhealthy: skip the health check, mark master as unhealthy, log `master health: cached unhealthy for <commit-hash>`.
  4. If not found: run `make test` and `make integration-test` as before, then write the result to the cache and commit.
- Cache writes committed to plan branch with message: `scriptorium: update health cache`.

**Relationship to in-memory cache:**
- The existing in-memory `MasterHealthState` cache continues to work within a session.
- The plan-branch cache augments it for cross-session persistence.
- Cache entries are keyed by commit hash and naturally immutable — no invalidation needed.

**Pruning:**
- Optional. The orchestrator may prune entries older than 30 days or keep the most recent N entries to prevent unbounded growth, but pruning is not required for v4.

**Plan branch layout addition:**
- `health/cache.json` is added to the authoritative plan branch file layout.

**V4 Known Limitations:**
- Health cache pruning is optional and not enforced — cache files may grow over time in long-running projects.
