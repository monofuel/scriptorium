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
