# Parallel Ticket Assignment By Area Independence

**Area:** parallel-execution

## Problem

The orchestrator currently assigns exactly one open ticket per tick via `executeOldestOpenTicket`. The V5 spec (§23) requires assigning multiple open tickets concurrently when they touch independent areas.

## Requirements

1. Add an `assignOpenTickets(repoPath, maxAgents)` proc that replaces the single-ticket `assignOldestOpenTicket` path:
   - Scan open tickets in ID order (oldest first).
   - Track which areas are "occupied" (have an in-progress ticket).
   - Assign each ticket whose area is not already occupied, up to `maxAgents` limit.
   - Same-area tickets are serialized — skip tickets whose area already has an in-progress ticket.
2. Each assigned ticket gets its own worktree and branch (`scriptorium/ticket-<id>`), same as existing single-ticket assignment.
3. When `maxAgents` is 1, behavior must be identical to the current single-ticket path.
4. Move ticket to `in-progress/` and record `**Worktree:**` field, same as current flow.
5. Return a sequence of assignment records for the caller to execute.
6. Add unit tests verifying:
   - Two tickets with different areas are both assigned when `maxAgents >= 2`.
   - Two tickets with the same area: only the oldest is assigned.
   - Assignment respects `maxAgents` cap.
   - `maxAgents = 1` assigns only one ticket.

## Acceptance Criteria

- `make test` passes with new tests.
- Existing single-ticket behavior preserved when `maxAgents = 1`.
- No changes to agent execution yet — this ticket only covers assignment logic.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0048-parallel-ticket-assignment

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 35
- reasoning: Requires implementing a new multi-ticket assignment proc with area-independence tracking, replacing the existing single-ticket path while preserving backward compatibility, plus unit tests — moderate logic but well-scoped with clear acceptance criteria and no agent execution changes.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0048-parallel-ticket-assignment/.scriptorium/logs/0048/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0048-parallel-ticket-assignment/.scriptorium/logs/0048/attempt-01.last_message.txt\n
### Agent Last Message
```text
All work is complete. Here's a summary of what was implemented:

**Changes made:**

1. **`src/scriptorium/orchestrator.nim`** — Added 3 new procs:
   - `openTicketsByIdInPlanPath` — Returns all open tickets sorted by numeric ID (ascending)
   - `inProgressAreasInPlanPath` — Collects area identifiers from in-progress tickets
   - `assignOpenTickets*(repoPath, maxAgents)` — Scans open tickets in ID order, tracks occupied areas (from existing in-progress tickets + batch), assigns each ticket whose area isn't occupied, up to `maxAgents`. Creates worktrees/branches per existing pattern. Commits all assignments in a single commit.

2. **`tests/test_scriptorium.nim`** — Added 6 unit tests in a "parallel ticket assignment" suite:
   - Two different areas both assigned when `maxAgents >= 2`
   - Same area: only oldest assigned
   - Respects `maxAgents` cap
   - `maxAgents = 1` assigns only one ticket
   - Skips areas already in-progress
   - Returns empty when no open tickets

All tests pass (`make test` exits 0). Backward compatibility preserved — when `maxAgents = 1`, only one ticket is assigned.
```

### Agent Stdout Tail
```text
rogress\n   - Returns empty when no open tickets\n\nAll tests pass (`make test` exits 0). Backward compatibility preserved — when `maxAgents = 1`, only one ticket is assigned.","stop_reason":"end_turn","session_id":"4e667556-81b4-4b48-a47f-fe3b8699a00a","total_cost_usd":1.7860202999999997,"usage":{"input_tokens":44,"cache_creation_input_tokens":52100,"cache_read_input_tokens":1985007,"output_tokens":9773,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":52100,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":44,"outputTokens":9773,"cacheReadInputTokens":1985007,"cacheCreationInputTokens":52100,"webSearchRequests":0,"costUSD":1.5626735000000003,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":1598,"outputTokens":5108,"cacheReadInputTokens":912238,"cacheCreationInputTokens":83988,"webSearchRequests":0,"costUSD":0.22334679999999998,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"41ed6e6d-031d-482b-a560-7ff878131e09"}
```
