# Per-Area Concurrent Manager Execution

**Area:** parallel-execution

**Depends:** 0068

## Problem

V13 §29 requires each eligible area to spawn an independent manager agent using the `manager_tickets.md` single-area prompt template, replacing the batched single-prompt model. Manager agents should generate ticket content in memory — only the orchestrator main thread writes to the plan worktree.

## Requirements

1. Create `proc buildManagerTicketsPrompt*(repoPath, planPath: string, areaId, areaRelPath, areaContent: string, nextId: int): string` in `prompt_builders.nim` using the existing `ManagerTicketsTemplate` from `prompt_catalog.nim`. The prompt should cover a single area.
2. Create `proc executeManagerForArea*(areaId, areaContent: string, repoPath, planPath: string, nextId: int, runner: AgentRunner): seq[string]` in `manager_agent.nim` that:
   - Builds the single-area prompt.
   - Runs the manager agent (using the `agents.manager` config for harness/model).
   - Parses generated ticket documents from agent output.
   - Returns ticket documents as a sequence of strings (in-memory, no filesystem writes).
3. Integrate with the shared agent pool from ticket 0068: manager agents use `startAgentAsync()` with `arManager` role, passing `executeManagerForArea` as the worker.
4. The orchestrator main thread handles manager completions from `checkCompletedAgents()`: acquires plan lock, calls a new `writeTicketsForArea()` proc to persist tickets, commits, releases lock.
5. Add `proc writeTicketsForArea*(planPath: string, areaId: string, ticketDocs: seq[string], nextId: int)` to `manager_agent.nim` that writes ticket files to `tickets/open/`.
6. `make test` must pass. Add unit tests for single-area prompt building and ticket document parsing.

## Notes

- The `manager_tickets.md` prompt template already exists in `src/scriptorium/prompts/`.
- Manager agents share the `maxAgents` slot pool with coding agents.
- Managers are prioritized over coders when slots are scarce (implemented in tick restructuring, ticket 0071).

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0069-per-area-concurrent-manager-execution
