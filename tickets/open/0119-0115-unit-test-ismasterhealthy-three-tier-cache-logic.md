# 0115 — Unit test isMasterHealthy three-tier cache logic

**Area:** health-cache

## Problem

The `isMasterHealthy` proc in `src/scriptorium/orchestrator.nim:48-99` implements three-tier caching (in-memory → file cache on plan branch → run checks). This core logic has no direct unit test. The existing tests in `tests/test_scriptorium.nim` only cover `readHealthCache`/`writeHealthCache` serialization.

## Task

Add unit tests to `tests/test_scriptorium.nim` in a new suite `"isMasterHealthy cache tiers"` that verify:

1. **In-memory hit:** When `MasterHealthState` is initialized with a matching HEAD, `isMasterHealthy` returns the cached value without reading the plan branch or running checks.
2. **File cache hit:** When the in-memory cache has a stale HEAD but `health/cache.json` contains the current HEAD, the file cache is used and no health check runs.
3. **Full miss:** When neither cache has the current HEAD, health checks run and the result is written to the file cache.

This requires creating a test helper that:
- Sets up a temporary git repo with a `scriptorium/plan` branch (use `git init`, `git commit --allow-empty`, `git branch scriptorium/plan`).
- Writes `health/cache.json` to the plan branch for the file-cache-hit test.
- Uses a mock/fake for `checkMasterHealth` (or calls `isMasterHealthy` with a repo where `make test` succeeds trivially).

Since `isMasterHealthy` is not exported (no `*`), you may need to either:
- Export it with `*` for testability, or
- Test it indirectly through `runOrchestratorForTicks` with a fake runner (pattern already used in `tests/integration_orchestrator_queue.nim`).

Use the project's test framework (`std/unittest`). Use `git_ops` helpers (`gitRun`, `gitCheck`) for repo setup — these are already available in the test file.

## Files
- `tests/test_scriptorium.nim`
- `src/scriptorium/orchestrator.nim` (if exporting `isMasterHealthy`)
````

````markdown
# 0116 — Add optional health cache pruning

**Area:** health-cache

## Problem

The health cache (`health/cache.json` on the plan branch) grows unboundedly as new master commits accumulate entries. The spec mentions optional pruning: keep the most recent N entries or prune entries older than 30 days.

## Task

Add a `pruneHealthCache` proc to `src/scriptorium/health_checks.nim` that:
1. Takes a `Table[string, HealthCacheEntry]` and a max-entries count (default 50).
2. Sorts entries by `timestamp` (ISO 8601, lexicographic sort works).
3. Removes the oldest entries if the table exceeds the limit.
4. Returns the pruned table.

Call `pruneHealthCache` in `isMasterHealthy` (in `src/scriptorium/orchestrator.nim`) after writing a new entry to the cache, before calling `commitHealthCache`. Use a constant `HealthCacheMaxEntries = 50` in `health_checks.nim`.

Add unit tests in `tests/test_scriptorium.nim`:
- A table with fewer entries than the limit is unchanged.
- A table exceeding the limit is pruned to exactly the limit, keeping the newest entries by timestamp.

Use `std/[algorithm, tables, times]` for sorting. Use `std/json` for JSON operations (already imported in health_checks.nim).

## Files
- `src/scriptorium/health_checks.nim`
- `src/scriptorium/orchestrator.nim`
- `tests/test_scriptorium.nim`
````
