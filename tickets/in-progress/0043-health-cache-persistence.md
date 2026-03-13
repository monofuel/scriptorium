# Persistent Health Cache On Plan Branch

**Area:** health-cache

## Problem

The orchestrator caches master health status in memory (`MasterHealthState` in `orchestrator.nim`), but this cache is lost on container restart or session boundary. The V4 spec (§22) requires a persistent cache at `health/cache.json` on the `scriptorium/plan` branch.

## Current State

- `MasterHealthState` object (lines ~148-152) tracks `head`, `healthy`, `initialized`, `lastHealthLogged`.
- `isMasterHealthy()` re-runs health checks when master HEAD changes.
- No file-based cache exists.

## Requirements

### Cache file structure

- Location: `health/cache.json` on the `scriptorium/plan` branch.
- JSON object mapping commit hashes to result records:
  ```json
  {
    "abc123": {
      "healthy": true,
      "timestamp": "2026-03-13T12:00:00Z",
      "test_exit_code": 0,
      "integration_test_exit_code": 0,
      "test_wall_seconds": 45,
      "integration_test_wall_seconds": 120
    }
  }
  ```

### Cache lookup flow

- When `isMasterHealthy()` is called (or equivalent), before running quality checks:
  1. Read `health/cache.json` from the plan worktree.
  2. Look up the current master HEAD commit.
  3. If found and healthy: skip health check, log `master health: cached healthy for <commit-hash>`, return true.
  4. If found and unhealthy: skip health check, log `master health: cached unhealthy for <commit-hash>`, return false.
  5. If not found: run `make test` and `make integration-test` as before.

### Cache write flow

- After running health checks for a commit not in cache:
  1. Write the result to `health/cache.json`.
  2. Commit to plan branch with message: `scriptorium: update health cache`.

### Integration with existing in-memory cache

- The in-memory `MasterHealthState` continues to work within a session.
- The file cache augments it for cross-session persistence.
- Check file cache only when the in-memory cache doesn't have the current commit.

## Implementation Notes

- Parse and serialize `health/cache.json` using `jsony` or `std/json`.
- Create `health/` directory on plan branch if it doesn't exist.
- Ensure the plan worktree is used for reading/writing (not the main repo).
- Cache entries are keyed by commit hash and naturally immutable — no invalidation needed.

## Acceptance Criteria

- `health/cache.json` is created and maintained on the plan branch.
- Cache hits skip health checks and log appropriately.
- Cache misses run health checks and persist results.
- Cache survives orchestrator restart (read from plan branch on startup).
- Unit tests cover cache hit (healthy), cache hit (unhealthy), and cache miss paths.
- Existing health check tests still pass.

## Spec References

- Section 22: Commit Health Cache (V4).

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0043-health-cache-persistence
