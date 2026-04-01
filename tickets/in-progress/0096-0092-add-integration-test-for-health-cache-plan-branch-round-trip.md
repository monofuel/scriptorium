# 0092 Add integration test for health cache plan-branch round-trip

**Area:** health-cache
**Priority:** medium
**Depends:** 0091

## Summary

Add an integration test that verifies the health cache can be written to and read from the plan branch, surviving a simulated orchestrator restart. This tests the full persistence path: write cache → commit to plan branch → read back from plan branch.

## Acceptance criteria

- Add a new test file `tests/integration_health_cache.nim`.
- The test should:
  1. Set up a temporary git repo with a `scriptorium/plan` branch.
  2. Write a `HealthCacheEntry` to `health/cache.json` using `writeHealthCache`.
  3. Commit using `commitHealthCache`.
  4. Simulate a "restart" by re-reading the plan branch from scratch (e.g., reset the worktree and call `readHealthCache` again).
  5. Assert the entry round-trips correctly with all fields preserved.
- This is an integration test — it must use real git operations (no mocks). Put it in `tests/integration_health_cache.nim`.
- Clean up temp directories after the test.

## Files to create

- `tests/integration_health_cache.nim`

## Notes

- Use `git init`, `git checkout -b scriptorium/plan`, etc. via `gitRun` from `scriptorium/git_ops` to set up the test repo.
- Import from `scriptorium/[health_checks, shared_state, git_ops]`.
- Use `std/[tables, os, osproc, unittest]`.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0096-0092-add-integration-test-for-health-cache-plan-branch-round-trip

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Single new integration test file requiring real git repo setup, health cache write/commit/read round-trip, and cleanup — moderate complexity from git operations and import wiring, but well-scoped with clear acceptance criteria and one attempt expected.
