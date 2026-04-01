# 0093 Implement optional health cache pruning

**Area:** health-cache
**Priority:** low

## Summary

The health cache (`health/cache.json`) grows unboundedly as new commits are checked. Implement an optional pruning step that keeps the most recent N entries (by timestamp) and removes older ones. This prevents the cache file from growing indefinitely in long-running projects.

## Acceptance criteria

- Add a `pruneHealthCache` proc to `src/scriptorium/health_checks.nim` that:
  - Accepts a `Table[string, HealthCacheEntry]` and a `maxEntries: int` parameter.
  - Returns a new table containing only the `maxEntries` most recent entries, sorted by `timestamp` (ISO 8601 string comparison is sufficient).
  - If the table has fewer entries than `maxEntries`, returns it unchanged.
- Add a constant `MaxHealthCacheEntries = 100` in `health_checks.nim`.
- Call `pruneHealthCache` in `isMasterHealthy` (in `orchestrator.nim`) just before `writeHealthCache`, passing the cache table and `MaxHealthCacheEntries`.
- Add unit tests for `pruneHealthCache` in `tests/test_health_checks.nim`:
  - Table with fewer entries than max is returned unchanged.
  - Table with more entries than max retains only the N most recent by timestamp.
  - Empty table returns empty.

## Files to modify

- `src/scriptorium/health_checks.nim` — add `pruneHealthCache` proc and constant.
- `src/scriptorium/orchestrator.nim` — call pruning before cache write.

## Files to modify (tests)

- `tests/test_health_checks.nim` — add pruning tests.

## Notes

- Use `std/[algorithm, sequtils]` for sorting. Use `&` for format strings.
- Since timestamps are ISO 8601, lexicographic string sort gives correct chronological order.
- Keep the implementation simple — no need for date parsing.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0097-0093-implement-optional-health-cache-pruning

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 11
- reasoning: Straightforward single-proc addition with simple sort logic across two source files and one test file, well-specified with no integration risk, one attempt expected.
