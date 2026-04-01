# 0091 Add unit tests for isMasterHealthy three-tier cache lookup

**Area:** health-cache
**Priority:** medium

## Summary

The `isMasterHealthy` proc in `src/scriptorium/orchestrator.nim` implements a three-tier cache lookup (in-memory → plan-branch file → live `make test`), but there are no unit tests covering this logic. The existing tests in `tests/test_shared_state.nim` only cover the lower-level `readHealthCache`/`writeHealthCache` functions.

## Acceptance criteria

- Add a new test file `tests/test_health_checks.nim` with a test suite covering:
  1. **In-memory cache hit:** When `MasterHealthState` is initialized and the HEAD hasn't changed, the cached result is returned without reading the file cache.
  2. **File cache hit (healthy):** When the in-memory cache misses but `health/cache.json` contains a healthy entry for the current HEAD, it returns `true` and logs the cached-healthy message.
  3. **File cache hit (unhealthy):** Same as above but for an unhealthy entry — returns `false` and logs the cached-unhealthy message.
  4. **Cache miss triggers live check:** When both caches miss, the health check runs and the result is written to the file cache.
- Since `isMasterHealthy` calls git operations and `make test`, the unit tests should test the cache read/write/lookup logic in isolation. Create a helper that exercises `readHealthCache` lookup keyed by commit hash, and test the `MasterHealthState` in-memory caching logic directly.
- Tests must follow project conventions: file named `tests/test_health_checks.nim`, uses `std/unittest`, no mocks of external services (this is a unit test file — test the pure logic portions).

## Files to create

- `tests/test_health_checks.nim`

## Notes

- Import from `scriptorium/health_checks` and `scriptorium/shared_state`.
- The `tests/config.nims` file already has `--path:"../src"` so imports will resolve.
- Use `std/[tables, os, json]` for table operations and temp directory creation. Use `&` for format strings.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0095-0091-add-unit-tests-for-ismasterhealthy-three-tier-cache-lookup
