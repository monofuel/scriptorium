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

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0096/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0096/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. The integration test in `tests/integration_health_cache.nim`:

1. Creates a temp git repo with a `scriptorium/plan` branch
2. Writes a `HealthCacheEntry` via `writeHealthCache`
3. Commits via `commitHealthCache`
4. Simulates restart by checking out the file from HEAD
5. Reads back with `readHealthCache` and asserts all 6 fields round-trip correctly
6. Cleans up temp directories via `defer`
```

### Agent Stdout Tail
```text
"num_turns":19,"result":"Done. The integration test in `tests/integration_health_cache.nim`:\n\n1. Creates a temp git repo with a `scriptorium/plan` branch\n2. Writes a `HealthCacheEntry` via `writeHealthCache`\n3. Commits via `commitHealthCache`\n4. Simulates restart by checking out the file from HEAD\n5. Reads back with `readHealthCache` and asserts all 6 fields round-trip correctly\n6. Cleans up temp directories via `defer`","stop_reason":"end_turn","session_id":"6de39386-48a7-4d17-8bab-7eb9c6864319","total_cost_usd":0.376707,"usage":{"input_tokens":16,"cache_creation_input_tokens":22418,"cache_read_input_tokens":323829,"output_tokens":2984,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":22418,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":16,"outputTokens":2984,"cacheReadInputTokens":323829,"cacheCreationInputTokens":22418,"webSearchRequests":0,"costUSD":0.376707,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"fce58f9e-a2d6-402b-b183-0c30948443c9"}
```
