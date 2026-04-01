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

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0097/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0097/attempt-01.last_message.txt\n
### Agent Last Message
```text
All done. Here's what was implemented:

- **`src/scriptorium/health_checks.nim`**: Added `MaxHealthCacheEntries = 100` constant and `pruneHealthCache` proc that sorts entries by timestamp descending and keeps only the most recent `maxEntries`.
- **`src/scriptorium/orchestrator.nim`**: Added `cache = pruneHealthCache(cache, MaxHealthCacheEntries)` call just before `writeHealthCache` in `isMasterHealthy`.
- **`tests/test_health_checks.nim`**: Added 3 tests covering fewer-than-max, more-than-max, and empty table cases. All 13 tests pass.
```

### Agent Stdout Tail
```text
100` constant and `pruneHealthCache` proc that sorts entries by timestamp descending and keeps only the most recent `maxEntries`.\n- **`src/scriptorium/orchestrator.nim`**: Added `cache = pruneHealthCache(cache, MaxHealthCacheEntries)` call just before `writeHealthCache` in `isMasterHealthy`.\n- **`tests/test_health_checks.nim`**: Added 3 tests covering fewer-than-max, more-than-max, and empty table cases. All 13 tests pass.","stop_reason":"end_turn","session_id":"31f6e5ca-fa9d-43df-9e8f-4ca5453a5be7","total_cost_usd":0.5060105,"usage":{"input_tokens":18,"cache_creation_input_tokens":29054,"cache_read_input_tokens":444916,"output_tokens":4075,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":29054,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":18,"outputTokens":4075,"cacheReadInputTokens":444916,"cacheCreationInputTokens":29054,"webSearchRequests":0,"costUSD":0.5060105,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"2403cbf2-88e1-4fce-8c8d-00f890c10ca8"}
```
