# Add unit test for staggered coding agent start

**Area:** parallel-execution
**Depends:** 0089

## Task

Add a test to `tests/test_orchestrator_flow.nim` in the
`"concurrent agent execution"` suite that verifies the staggered start rule:
only 1 new coding agent starts per orchestrator tick.

### Test design

1. Create a test repo with 3 open tickets in different areas (area-a, area-b,
   area-c) and set `maxAgents: 4`.
2. Use a fake runner that:
   - Handles architect and manager calls as no-ops.
   - For coding agents: records the tick on which each ticket's coding call
     occurs (use a shared counter incremented per tick by counting
     `runOrchestratorForTicks` calls).
   - Calls `recordSubmitPrSummary` immediately so tickets complete in one
     coding call.
3. Run `runOrchestratorForTicks(tmp, 5, fakeRunner)`.
4. Assert that coding agents for the 3 tickets were started on 3 different
   ticks (not all on the same tick).

Use the existing `helpers` module and test patterns from the file. The test
helper `addTicketToPlan`, `addPassingMakefile`, and `writeScriptoriumConfig`
are already available.

Run `make test` to verify the new test passes.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0090-add-unit-test-for-staggered-coding-agent-start

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Single-file test addition to an existing suite with clear design spec, but requires understanding orchestrator tick mechanics and fake runner patterns, moderate complexity in tracking per-tick agent starts.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0090/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0090/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. The test has been added and submitted:

- **File**: `tests/test_orchestrator_flow.nim` — new test `"staggered start: only 1 new coding agent starts per tick"` in the `"concurrent agent execution"` suite
- **Design**: Creates 3 tickets (area-a, area-b, area-c) with `maxAgents: 4`, tracks tick numbers via a shared counter incremented on architect calls, and asserts all 3 coding agents started on 3 distinct ticks
- **All tests pass** (`make test` clean)
```

### Agent Stdout Tail
```text
: `tests/test_orchestrator_flow.nim` — new test `\"staggered start: only 1 new coding agent starts per tick\"` in the `\"concurrent agent execution\"` suite\n- **Design**: Creates 3 tickets (area-a, area-b, area-c) with `maxAgents: 4`, tracks tick numbers via a shared counter incremented on architect calls, and asserts all 3 coding agents started on 3 distinct ticks\n- **All tests pass** (`make test` clean)","stop_reason":"end_turn","session_id":"50f39bf4-9607-45d2-9095-74cfa6bf742c","total_cost_usd":0.963209,"usage":{"input_tokens":213,"cache_creation_input_tokens":64076,"cache_read_input_tokens":830088,"output_tokens":5865,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":64076},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":213,"outputTokens":5865,"cacheReadInputTokens":830088,"cacheCreationInputTokens":64076,"webSearchRequests":0,"costUSD":0.963209,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"0f19bb87-a470-4050-b73e-bed9a971875d"}
```

## Review
**Review:** approved with warnings
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 3m42s

**Warnings:** Minor: Line 1294 (`check tickValues[0] != tickValues[1] or tickValues[1] != tickValues[2]`) is redundant with line 1295 (`check tickValues.deduplicate().len == 3`). The deduplicate check is strictly stronger — if all 3 deduplicated values remain, they must all be distinct. The weaker OR check on line 1294 could be removed without loss of coverage.

**Review Reasoning:** ghly equivalent — but it's not exactly "per tick." If the architect doesn't run on some ticks (e.g., after areas are already generated), the counter wouldn't increment.

Let me check what `runOrchestratorForTicks` does to understand if the architect is called on every tick.
I've now reviewed the full context. Let me verify one more thing about the `deduplicate` function behavior.
`deduplicate` is from `std/sequtils` (already imported). It removes consecutive duplicates, so it works correctly on the sorted sequence.

Here's my review summary:

**Test design**: Correct and follows the ticket spec. Creates 3 tickets in different areas, sets `maxAgents: 4`, tracks tick numbers via architect calls, asserts all 3 started on different ticks.

**Tick tracking mechanism**: Works because the fake runner never writes area files, so `areasMissingInPlanPath` stays true and the architect runs every tick, incrementing the counter. There's a theoretical race between the async coding agent thread recording the tick and the next tick's architect incrementing the counter, but the fake runner is trivially fast and the orchestrator does significant synchronous work between ticks, making this safe in practice.

**Convention compliance**: Follows existing patterns — camelCase variables, Lock usage with `{.cast(gcsafe).}`, no new imports needed, same test setup helpers.

**Minor issue**: Line 1294 (`check tickValues[0] != tickValues[1] or tickValues[1] != tickValues[2]`) is strictly weaker than line 1295 (`check tickValues.deduplicate().len == 3`). The first check allows 2-of-3 to match (e.g., `[1, 1, 2]` passes), while the second requires all 3 to be distinct. The redundant check adds no value — the `deduplicate().len == 3` assertion is sufficient on its own. Not a correctness issue, just unnecessary noise.
Approved with a minor warning about the redundant assertion on line 1294. The test is well-structured, follows existing patterns, and correctly verifies the staggered start rule.

## Merge Queue Success
- Summary: Added unit test for staggered coding agent start in the "concurrent agent execution" suite. The test creates 3 tickets in different areas with maxAgents=4, uses a fake runner that tracks the tick on which each coding call occurs via a shared counter incremented on architect calls, and asserts all 3 tickets started on 3 different ticks (not batched on the same tick).\n
### Quality Check Output
```text
] [2026-03-23T22:02:26Z] [INFO] journal: transition complete
[tests/integration_orchestrator_queue.nim] [2026-03-23T22:02:26Z] [INFO] merge queue: item processed
[tests/integration_orchestrator_queue.nim] [2026-03-23T22:02:26Z] [INFO] tick 0 summary: architect=updated manager=no-op coding=1/4 agents merge=processing open=0 in-progress=0 done=1
[tests/integration_orchestrator_queue.nim] [2026-03-23T22:02:27Z] [INFO] shutdown: waiting for 1 running agent(s)
[tests/integration_orchestrator_queue.nim] [2026-03-23T22:03:02Z] [INFO] session summary: uptime=1m46s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[tests/integration_orchestrator_queue.nim] [2026-03-23T22:03:02Z] [INFO] session summary: avg_ticket_wall=33s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
[tests/integration_orchestrator_queue.nim]   [OK] IT-10 global halt while red resumes after master health is restored
[tests/integration_orchestrator_queue.nim] [2026-03-23T22:03:02Z] [INFO] orchestrator PID guard acquired (PID 85616)
[tests/integration_orchestrator_queue.nim] [2026-03-23T22:03:02Z] [INFO] recovery: clean startup, no recovery needed
[tests/integration_orchestrator_queue.nim] [2026-03-23T22:03:03Z] [WARN] master is unhealthy — skipping tick
[tests/integration_orchestrator_queue.nim] [2026-03-23T22:03:33Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[tests/integration_orchestrator_queue.nim] [2026-03-23T22:03:33Z] [INFO] session summary: avg_ticket_wall=33s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
[tests/integration_orchestrator_queue.nim]   [OK] IT-11 integration-test failure on master blocks assignment of open tickets
[tests/integration_orchestrator_queue.nim] Error: execution of an external program failed: '/home/scriptorium/.cache/nim/integration_orchestrator_queue_d/integration_orchestrator_queue_1E9F66947A2A25BC8B5DD54C960C46F4DBB719CD'
```

## Metrics
- wall_time_seconds: 1420
- coding_wall_seconds: 795
- test_wall_seconds: 395
- attempt_count: 1
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 340788

## Post-Analysis
- actual_difficulty: medium
- prediction_accuracy: accurate
- brief_summary: Predicted medium, actual was medium with 1 attempt(s) in 23m40s.
