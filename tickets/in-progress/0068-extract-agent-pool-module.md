# Extract Agent Pool Module With AgentRole Enum

**Area:** parallel-execution

## Problem

V13 §28 requires a shared `agent_pool` module extracted from `coding_agent.nim` with an `AgentRole` enum so managers and coding agents share a single `maxAgents` slot pool. Currently agent slot management lives entirely in `coding_agent.nim` and only tracks coding agents.

## Requirements

1. Create `src/scriptorium/agent_pool.nim` module extracted from `coding_agent.nim`.
2. Define `AgentRole` enum with values `arCoder` and `arManager`.
3. Extend `AgentSlot` with a `role: AgentRole` field. Manager slots use `areaId` as identifier and have no branch or worktree (empty strings). Coder slots retain `ticketId`, `branch`, and `worktree`.
4. Define `AgentCompletionResult` with a `role` field and an optional `managerResult` (sequence of generated ticket document strings) alongside existing coding result fields.
5. Implement `startAgentAsync()` that accepts a role and a generic worker proc. Coding agents pass `executeAssignedTicket` wrapper; manager agents will pass `executeManagerForArea` wrapper (to be implemented in ticket 0069).
6. Implement `checkCompletedAgents()` that returns completions tagged with role for orchestrator dispatch.
7. Slot arithmetic: if `maxAgents` is 4 and 2 managers are running, only 2 slots remain for coding agents (and vice versa).
8. Move `runningAgentCount()`, `emptySlotCount()`, `joinAllAgentThreads()` into the new module.
9. Update `coding_agent.nim` and `orchestrator.nim` to import from `agent_pool` instead of using local slot management.
10. `make test` must pass. Add unit tests for role-tagged slot counting and completion result dispatch.

## Notes

- The existing `AgentSlot` is defined in `shared_state.nim` (lines 125-129) and slot sequences are in `coding_agent.nim` (lines 29-30).
- Architect and review/merge remain strictly sequential and do not consume pool slots.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0068-extract-agent-pool-module

## Prediction
- predicted_difficulty: hard
- predicted_duration_minutes: 30
- reasoning: Extracting a new module from existing code, defining new types (AgentRole enum, extended AgentSlot, AgentCompletionResult), implementing generic startAgentAsync/checkCompletedAgents, updating imports across coding_agent.nim and orchestrator.nim, plus adding unit tests — significant cross-module refactor with integration risk likely requiring 2+ attempts.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 5\n- Attempt Count: 5\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0068-extract-agent-pool-module/.scriptorium/logs/0068/attempt-05.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0068-extract-agent-pool-module/.scriptorium/logs/0068/attempt-05.last_message.txt\n
### Agent Last Message
```text
Stale notification — already processed. All work is complete and the PR has been submitted.
```

### Agent Stdout Tail
```text
_tokens":0},"output_tokens":9},"context_management":null},"parent_tool_use_id":null,"session_id":"dd32ad2b-0cdf-40a7-afa5-4588ed9c06c7","uuid":"4302ab8f-22da-466f-8607-f795cf862d9c"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":2358,"duration_api_ms":148168,"num_turns":1,"result":"Stale notification — already processed. All work is complete and the PR has been submitted.","stop_reason":"end_turn","session_id":"dd32ad2b-0cdf-40a7-afa5-4588ed9c06c7","total_cost_usd":1.1646299999999998,"usage":{"input_tokens":3,"cache_creation_input_tokens":388,"cache_read_input_tokens":51515,"output_tokens":22,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":388},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":19460,"outputTokens":5577,"cacheReadInputTokens":1261760,"cacheCreationInputTokens":47524,"webSearchRequests":0,"costUSD":1.1646299999999998,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"6ed036be-ab7f-42f5-a909-7a6341c1806b"}
```
