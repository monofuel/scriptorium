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
