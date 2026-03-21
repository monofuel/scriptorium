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
