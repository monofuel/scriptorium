# Add unit test for manager priority over coders

**Area:** parallel-execution

## Task

Add a test to `tests/test_orchestrator_flow.nim` in the
`"concurrent agent execution"` suite that verifies managers are prioritized
over coding agents when slots are scarce.

### Test design

1. Create a test repo with `maxAgents: 2`.
2. Write a spec and configure it so the architect produces 2 areas that both
   need tickets.
3. Add 1 open ticket in area-a so a coding agent is also eligible.
4. Use a fake runner that tracks the order of agent invocations by `ticketId`:
   - Architect: writes 2 area files.
   - Manager agents: return ticket documents.
   - Coding agent: calls `recordSubmitPrSummary`.
5. Run `runOrchestratorForTicks(tmp, 4, fakeRunner)`.
6. Assert that in the tick where both a manager and a coding agent are
   eligible, the manager starts first (i.e., manager `ticketId` entries appear
   before the coding agent `ticketId` in the call order for that tick).

This validates the tick order guarantee: step 5 (managers) runs before step 6
(coders).

Run `make test` to verify the new test passes.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0091-add-unit-test-for-manager-priority-over-coders

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Single-file test addition but requires understanding the existing test infrastructure (fake runners, runOrchestratorForTicks, test repo setup) and carefully orchestrating multi-agent scenario with specific assertion on tick ordering.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0091/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0091/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Added a test `"managers are prioritized over coding agents when slots are scarce"` to the `"concurrent agent execution"` suite in `tests/test_orchestrator_flow.nim`. The test:

1. Creates a repo with `maxAgents: 2`
2. Writes a spec so the architect produces 2 areas (area-a, area-b)
3. Pre-adds 1 open ticket in area-a so a coding agent is eligible
4. Uses a fake runner with a lock-protected `callOrder` seq tracking invocations by ticketId
5. Runs `runOrchestratorForTicks(tmp, 4, fakeRunner)`
6. Asserts `manager-area-b` appears before `0001` in the call order, validating the tick order guarantee (step 5 managers before step 6 coders)
```

### Agent Stdout Tail
```text
oduces 2 areas (area-a, area-b)\n3. Pre-adds 1 open ticket in area-a so a coding agent is eligible\n4. Uses a fake runner with a lock-protected `callOrder` seq tracking invocations by ticketId\n5. Runs `runOrchestratorForTicks(tmp, 4, fakeRunner)`\n6. Asserts `manager-area-b` appears before `0001` in the call order, validating the tick order guarantee (step 5 managers before step 6 coders)","stop_reason":"end_turn","session_id":"2bc443e8-6e37-4bb2-b326-83e68f9c7163","total_cost_usd":1.0941310000000002,"usage":{"input_tokens":24,"cache_creation_input_tokens":65136,"cache_read_input_tokens":1030922,"output_tokens":6858,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":65136},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":24,"outputTokens":6858,"cacheReadInputTokens":1030922,"cacheCreationInputTokens":65136,"webSearchRequests":0,"costUSD":1.0941310000000002,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"3b3a66a4-0316-4b28-90e7-0c3294687b8d"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 30s

**Review Reasoning:** Let me read the surrounding test context to understand the patterns used.
The test follows existing patterns well. Let me verify imports at the top of the file to check if `find` is available.
The test looks correct. `find` is from `sequtils` which is already imported. The code follows existing patterns (Lock usage, `{.cast(gcsafe).}`, `AgentRunResult` construction, `defer: removeDir`).

Let me verify the ticket requirements against the implementation:

1. **maxAgents: 2** — Done (line 1308)
2. **Architect produces 2 areas** — Done (lines 1323-1324)
3. **1 open ticket in area-a** — Done (line 1305)
4. **Fake runner tracks order by ticketId** — Done (lines 1317-1320)
5. **runOrchestratorForTicks(tmp, 4, fakeRunner)** — Done (line 1345)
6. **Assert manager starts before coder** — Done (lines 1357-1361)

Convention checks:
- Import style: no new imports added, existing style is correct
- Variable naming: camelCase (`callOrder`, `callOrderLock`, `finalOrder`, `managerIdx`, `coderIdx`) — correct
- Doc comment on the proc inside the closure — present
- Comments are complete sentences with punctuation — yes
- No try/catch, no boolean success/error — correct
- Lock properly initialized, acquired, released, deinitialized — correct

The implementation is clean and matches the ticket requirements precisely.
**Approved.** The test correctly validates the manager-before-coder priority guarantee. It follows existing test patterns, uses proper lock discipline, and the assertion (`managerIdx < coderIdx`) cleanly verifies the tick ordering from the spec (step 5 managers before step 6 coders). No convention or quality issues.
