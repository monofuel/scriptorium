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

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 1m19s

**Review Reasoning:** Let me review the integration test implementation.
The implementation looks clean. Let me verify it matches all acceptance criteria:

- **Temp git repo with `scriptorium/plan` branch**: `makeTestRepo` creates this correctly.
- **Writes `HealthCacheEntry` via `writeHealthCache`**: Done at line 44.
- **Commits via `commitHealthCache`**: Done at line 45.
- **Simulates restart by re-reading from plan branch**: `git checkout HEAD -- ...` at line 53 proves the file comes from the commit, then `readHealthCache` at line 55 re-reads.
- **Asserts all 6 fields round-trip**: Lines 60-65 check all fields.
- **Real git operations, no mocks**: Confirmed — this is a proper integration test.
- **Cleanup via `defer`**: Line 26-27.

**Convention check**:
- Import style: Single block, bracket syntax, std/ first then local.
- Doc comment on `makeTestRepo`.
- camelCase variables, no grouping issues.
- No try/catch, no boolean success patterns.
- No unused imports (`osproc` used for `execCmdEx`, `os` for path ops and `dirExists`/`createDir`/`removeDir`, `tables` for `initTable`/`hasKey`, `unittest` for test framework).

**Note on `execCmdEx` vs `gitRun`**: The ticket notes suggest using `gitRun` from `git_ops`, but the established pattern across all other integration tests (`integration_journal.nim`, `integration_recovery.nim`, etc.) is `discard execCmdEx(...)` for git setup. The implementation follows the existing codebase convention, which is fine.
The integration test is well-written and meets all acceptance criteria. It correctly exercises the full health cache persistence path (write → commit → re-read from committed state) using real git operations, verifies all 6 fields round-trip, and cleans up after itself. Approved.

## Merge Queue Success
- Summary: Added integration test for health cache plan-branch round-trip in tests/integration_health_cache.nim. The test sets up a temp git repo with a scriptorium/plan branch, writes a HealthCacheEntry, commits it, then re-reads from the committed state and asserts all fields are preserved.\n
### Quality Check Output
```text
strator_flow.nim]  1188 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
[tests/integration_orchestrator_flow.nim] /home/scriptorium/.cache/nim/integration_orchestrator_flow_d/@pjson.nim.c:2883:1: fatal error: error writing to /dev/shm/ccrU1ZaP.s: No space left on device
[tests/integration_orchestrator_flow.nim]  2883 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
[tests/integration_orchestrator_flow.nim] /home/scriptorium/.cache/nim/integration_orchestrator_flow_d/@pstrutils.nim.c:3537:1: fatal error: error writing to /dev/shm/cc9z9QWg.s: No space left on device
[tests/integration_orchestrator_flow.nim]  3537 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
[tests/integration_orchestrator_flow.nim] /home/scriptorium/.cache/nim/integration_orchestrator_flow_d/@ptimes.nim.c:3801:1: fatal error: error writing to /dev/shm/cchEpHxy.s: No space left on device
[tests/integration_orchestrator_flow.nim]  3801 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
[tests/integration_orchestrator_flow.nim] /home/scriptorium/.cache/nim/integration_orchestrator_flow_d/@ptables.nim.c:8698:1: fatal error: error writing to /dev/shm/cc57OpnY.s: No space left on device
[tests/integration_orchestrator_flow.nim]  8698 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
[tests/integration_orchestrator_flow.nim] /home/scriptorium/.cache/nim/integration_orchestrator_flow_d/@psystem.nim.c:14454:1: fatal error: error writing to /dev/shm/ccospeMD.s: No space left on device
[tests/integration_orchestrator_flow.nim] 14454 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
```

## Metrics
- wall_time_seconds: 368
- coding_wall_seconds: 66
- test_wall_seconds: 17
- attempt_count: 1
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 102389

## Post-Analysis
- actual_difficulty: easy
- prediction_accuracy: overestimated
- brief_summary: Predicted medium, actual was easy with 1 attempt(s) in 6m8s.
