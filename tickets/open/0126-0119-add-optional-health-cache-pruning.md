# 0119 — Add optional health cache pruning

**Area:** health-cache

## Problem

The health cache (`health/cache.json` on the plan branch) grows by one entry per
unique master commit. Over time this file will grow unboundedly. The spec notes
that pruning is optional but recommended.

## Task

Add a `pruneHealthCache` proc in `src/scriptorium/health_checks.nim` that:

1. Accepts the cache table (`Table[string, HealthCacheEntry]`) and a max entry
   count (default 100).
2. If the table exceeds the max, sorts entries by `timestamp` (ISO 8601 string
   comparison is sufficient) and removes the oldest entries until the table is at
   the limit.
3. Returns the pruned table.

Call `pruneHealthCache` in `isMasterHealthy` in `src/scriptorium/orchestrator.nim`
(around line 92) just before `writeHealthCache`, so the cache is pruned on every
write.

Add unit tests in `tests/test_scriptorium.nim`:
- A cache with fewer entries than the limit is unchanged.
- A cache exceeding the limit is pruned to exactly the limit, keeping the most
  recent entries by timestamp.

Use `std/[algorithm, tables, times]` — no additional dependencies needed.
