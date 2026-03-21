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

## Review
**Review:** changes requested
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 54s

**Review Feedback:** The core types (AgentRole, AgentSlot, AgentCompletionResult) and slot counting procs are correctly implemented, and the tests are good. However, the module extraction is incomplete:

1. **Missing generic `startAgentAsync()`** (Req 5): The ticket requires a single `startAgentAsync()` that accepts a role and a generic worker proc. Instead, only `startCodingAgentAsync()` exists, which hardcodes `arCoder` and doesn't accept a worker proc parameter. Implement a generic version in `agent_pool.nim` — the worker proc can be typed as a callback that the caller provides. `startCodingAgentAsync` can then be a thin wrapper that calls `startAgentAsync(arCoder, ...)`.

2. **`joinAllAgentThreads()` not moved** (Req 8): Move this proc into `agent_pool.nim`. Thread tracking (the `codingAgentThreads` table or a generalized equivalent) needs to live in the pool module to support this.

3. **`checkCompletedAgents()` not in agent_pool** (Req 6): Move this into `agent_pool.nim`. The thread-joining logic within it should work against pool-level thread tracking rather than the coding-specific `codingAgentThreads` table.

The goal is for `agent_pool.nim` to be the actual pool manager (start, check, join), not just a types+counting module. Ticket 0069 (manager agents) should be able to import `agent_pool` and call `startAgentAsync(arManager, executeManagerForArea)` without touching `coding_agent.nim`.

## Prediction
- predicted_difficulty: hard
- predicted_duration_minutes: 30
- reasoning: Cross-module extraction creating a new agent_pool module, defining multiple new types (AgentRole, extended AgentSlot, AgentCompletionResult), implementing generic startAgentAsync/checkCompletedAgents, moving thread management procs, and updating imports across coding_agent.nim and orchestrator.nim — review feedback confirms incomplete extraction needed multiple attempts.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 2\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0068-extract-agent-pool-module/.scriptorium/logs/0068/attempt-02.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0068-extract-agent-pool-module/.scriptorium/logs/0068/attempt-02.last_message.txt\n
### Agent Last Message
```text
The background `make test` task completed (exit code 0) — consistent with what I already verified. All work is committed and the PR has been submitted.
```

### Agent Stdout Tail
```text
},"parent_tool_use_id":null,"session_id":"fa052dc4-c7b0-4eae-9d31-721077353da1","uuid":"64acaf38-1dc3-479d-8a68-eae2317a735e"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":3834,"duration_api_ms":110441,"num_turns":1,"result":"The background `make test` task completed (exit code 0) — consistent with what I already verified. All work is committed and the PR has been submitted.","stop_reason":"end_turn","session_id":"fa052dc4-c7b0-4eae-9d31-721077353da1","total_cost_usd":0.9023720000000001,"usage":{"input_tokens":3,"cache_creation_input_tokens":485,"cache_read_input_tokens":51299,"output_tokens":36,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":485},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":30,"outputTokens":4367,"cacheReadInputTokens":938794,"cacheCreationInputTokens":51784,"webSearchRequests":0,"costUSD":0.9023720000000001,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"0dcb235a-7e7a-4c34-b629-3ac34de350b9"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 33s

## Merge Queue Success
- Summary: Extract agent_pool module from coding_agent.nim with AgentRole enum (arCoder/arManager), generic startAgentAsync accepting role and worker proc, checkCompletedAgents with role-tagged completions, joinAllAgentThreads, and shared slot arithmetic. Includes unit tests for slot counting and completion dispatch.\n
### Quality Check Output
```text
2026-03-21T11:35:18Z] [INFO] ticket 0002: saved uncommitted agent work before retry
[2026-03-21T11:35:18Z] [INFO] ticket 0002: coding agent started (model=claude-sonnet-4-6, attempt 5/5)
[2026-03-21T11:35:57Z] [INFO] ticket 0002: coding agent finished (exit=0, wall=38s, stall=true)
[2026-03-21T11:35:57Z] [INFO] ticket 0002: in-progress -> open (reopened, reason=no submit_pr, attempts=5, total wall=11m32s)
[2026-03-21T11:35:57Z] [INFO] ticket 0002: post-analysis: predicted=medium actual=complex accuracy=underestimated wall=11m32s
[2026-03-21T11:35:57Z] [INFO] journal: began transition — reopen 0002
[2026-03-21T11:35:57Z] [INFO] journal: executed steps — reopen 0002
[2026-03-21T11:35:57Z] [INFO] journal: transition complete
[2026-03-21T11:35:57Z] [INFO] session summary: uptime=13m9s ticks=1 tickets_completed=3 tickets_reopened=4 tickets_parked=0 merge_queue_processed=3
[2026-03-21T11:35:57Z] [INFO] session summary: avg_ticket_wall=48s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-10 global halt while red resumes after master health is restored
[2026-03-21T11:35:57Z] [INFO] recovery: clean startup, no recovery needed
[2026-03-21T11:35:57Z] [INFO] agent slots: 0/4 (ticket 0002 finished)
[2026-03-21T11:35:58Z] [WARN] master is unhealthy — skipping tick
[2026-03-21T11:36:28Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=3 tickets_reopened=4 tickets_parked=0 merge_queue_processed=3
[2026-03-21T11:36:28Z] [INFO] session summary: avg_ticket_wall=48s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-11 integration-test failure on master blocks assignment of open tickets
--- tests/integration_review_agent_live.nim ---

[Suite] integration review agent live
  [OK] IT-REVIEW-01 real review agent calls submit_review with a real model
--- tests/integration_typoi_harness.nim ---

[Suite] integration typoi harness
  [SKIPPED] real typoi one-shot smoke test
  [SKIPPED] real typoi MCP tool call against live server
```

## Metrics
- wall_time_seconds: 7545
- coding_wall_seconds: 4936
- test_wall_seconds: 2568
- attempt_count: 2
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 230994

## Post-Analysis
- actual_difficulty: hard
- prediction_accuracy: accurate
- brief_summary: Predicted hard, actual was hard with 2 attempt(s) in 2h5m.
