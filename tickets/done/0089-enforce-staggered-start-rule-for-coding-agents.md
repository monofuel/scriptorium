# Enforce staggered start rule for coding agents

**Area:** parallel-execution

## Problem

The orchestrator parallel path (`maxAgents > 1`) passes `slotsAvailable` to
`assignOpenTickets` and starts ALL returned assignments in one tick
(`src/scriptorium/orchestrator.nim` lines 291–296). The area spec requires
"at most 1 new coding agent per tick" to avoid burst-spawning.

## Task

In `runOrchestratorMainLoop` (file `src/scriptorium/orchestrator.nim`), change
the parallel coding agent start block (step 6) so that:

1. Call `assignOpenTickets(repoPath, 1)` instead of
   `assignOpenTickets(repoPath, slotsAvailable)` — this assigns at most one
   ticket per tick while still respecting area independence and dependency
   checks.
2. Keep the existing stall/submission handling, prediction, and
   `startCodingAgentAsync` call unchanged.
3. The `slotsAvailable > 0` guard remains so no assignment is attempted when
   the pool is full.

This is a one-line change: replace the second argument from `slotsAvailable`
to `1`.

Verify `make test` passes after the change.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0089-enforce-staggered-start-rule-for-coding-agents

## Prediction
- predicted_difficulty: trivial
- predicted_duration_minutes: 5
- reasoning: Explicit one-line change replacing `slotsAvailable` with `1` in a single function call, with clear location and no integration risk.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0089/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0089/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changed `assignOpenTickets(repoPath, slotsAvailable)` to `assignOpenTickets(repoPath, 1)` at line 292 of `src/scriptorium/orchestrator.nim`, enforcing the one-agent-per-tick staggered start rule. All tests pass.
```

### Agent Stdout Tail
```text
9-816c-4cf7-9136-f68e3ed656ee","uuid":"dddc3e21-144c-4ce6-b195-add85b0721da"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":194586,"duration_api_ms":29477,"num_turns":7,"result":"Done. Changed `assignOpenTickets(repoPath, slotsAvailable)` to `assignOpenTickets(repoPath, 1)` at line 292 of `src/scriptorium/orchestrator.nim`, enforcing the one-agent-per-tick staggered start rule. All tests pass.","stop_reason":"end_turn","session_id":"595fa349-816c-4cf7-9136-f68e3ed656ee","total_cost_usd":0.153023,"usage":{"input_tokens":10,"cache_creation_input_tokens":14750,"cache_read_input_tokens":73171,"output_tokens":968,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":14750},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":10,"outputTokens":968,"cacheReadInputTokens":73171,"cacheCreationInputTokens":14750,"webSearchRequests":0,"costUSD":0.153023,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"8abee85b-e654-43ca-a808-be6d6e2e5f2c"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 21s

**Review Reasoning:** The diff is a single-line change replacing `slotsAvailable` with `1` in the `assignOpenTickets` call. This exactly matches the ticket requirements and the spec's staggered start rule ("at most 1 new coding agent per tick"). The `slotsAvailable > 0` guard is preserved, and no other code is modified.

No convention violations, no spec contradictions, no dead code, no unrelated changes.
Review submitted: **approved**. Clean one-line change that correctly enforces the staggered start rule.
