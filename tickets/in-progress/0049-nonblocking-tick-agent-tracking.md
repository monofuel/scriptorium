# Non-Blocking Orchestrator Tick With Agent Process Tracking

**Area:** parallel-execution

## Problem

The orchestrator tick currently blocks on `executeAssignedTicket` until the single coding agent exits. The V5 spec (§24) requires that the tick must not block on any single agent — it must check for completable agents, start new agents, and continue other tick phases while agents run.

## Requirements

1. Add an `AgentSlot` type tracking:
   - Running process handle (or thread)
   - Associated ticket ID, branch, worktree path
   - Start time
2. Add an `AgentPool` (or equivalent) that holds up to `maxAgents` active slots.
3. Refactor the main tick loop so that:
   - At the start of the tick, check for completed agents (exited processes). For each completed agent, run the existing post-execution logic (agent run notes, metrics, submit_pr consumption, merge queue enqueueing).
   - After architect/manager phases, assign new tickets to empty slots via the parallel assignment logic from ticket 0048.
   - Start coding agent processes for newly assigned tickets (non-blocking).
   - Continue to merge queue processing without waiting for agents.
4. Agent lifecycle (stall detection, continuation, submit_pr) applies independently per agent slot.
5. Log agent slot changes: `agent slots: <running>/<max> (ticket <id> started|finished)`.
6. When `maxAgents = 1`, behavior must match the current serial execution.

## Dependencies

- Ticket 0045 (concurrency config keys)
- Ticket 0048 (parallel ticket assignment)

## Acceptance Criteria

- `make test` passes.
- Tick does not block on agent execution when `maxAgents > 1`.
- Serial behavior preserved when `maxAgents = 1`.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0049-nonblocking-tick-agent-tracking

## Prediction
- predicted_difficulty: hard
- predicted_duration_minutes: 55
- reasoning: Requires introducing new AgentSlot/AgentPool abstractions, refactoring the core tick loop from blocking to non-blocking process management, wiring up per-slot lifecycle handling, and ensuring backward compatibility with serial mode—touching orchestration, process management, and post-execution logic across multiple modules.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0049-nonblocking-tick-agent-tracking/.scriptorium/logs/0049/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0049-nonblocking-tick-agent-tracking/.scriptorium/logs/0049/attempt-01.last_message.txt\n
### Agent Last Message
```text
eTicketWorktree`, `clearActiveTicketWorktree`, `getActiveTicketWorktree` all now accept optional `ticketId` parameter
- Added optional `ticket_id` parameter to the `submit_pr` MCP tool schema for parallel mode

### Agent Pool Infrastructure
- `agentWorkerThread`: Runs `executeAssignedTicket` in a background thread
- `startAgentAsync`: Creates thread and slot for an assignment
- `checkCompletedAgents`: Polls result channel for finished agents, joins threads
- `joinAllAgentThreads`: Graceful shutdown cleanup
- `runningAgentCount` / `emptySlotCount`: Pool status queries
- Added `timingsLock` for thread-safe timing table access

### Tick Loop Refactoring
- **Serial mode (maxAgents=1)**: Identical blocking behavior via `executeOldestOpenTicket`
- **Parallel mode (maxAgents>1)**: Checks for completed agents, assigns tickets to empty slots via `assignOpenTickets`, starts agents non-blocking, continues to merge queue
- Agent slot changes logged as: `agent slots: <running>/<max> (ticket <id> started|finished)`
- Graceful shutdown waits for running agent threads

### Tests
- 8 new tests across 3 suites: per-ticket submit_pr state, agent slot types, non-blocking tick loop
- All 224 tests pass
```

### Agent Stdout Tail
```text
|finished)`\n- Graceful shutdown waits for running agent threads\n\n### Tests\n- 8 new tests across 3 suites: per-ticket submit_pr state, agent slot types, non-blocking tick loop\n- All 224 tests pass","stop_reason":"end_turn","session_id":"7c408661-2981-491d-a17b-e8248a31abb5","total_cost_usd":6.64284575,"usage":{"input_tokens":82,"cache_creation_input_tokens":131075,"cache_read_input_tokens":8436056,"output_tokens":53284,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":131075,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":82,"outputTokens":53284,"cacheReadInputTokens":8436056,"cacheCreationInputTokens":131075,"webSearchRequests":0,"costUSD":6.36975675,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":27,"outputTokens":8975,"cacheReadInputTokens":1376345,"cacheCreationInputTokens":72442,"webSearchRequests":0,"costUSD":0.273089,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"92f053ca-0634-4b09-8d84-998b02406892"}
```

## Review
**Review:** approved
- Model: codex-fake-unit-test-model
- Backend: claude-code
- Exit Code: 1
- Wall Time: 7s
