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
