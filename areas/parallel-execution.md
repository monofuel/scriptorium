# Multi-Ticket Parallelism And Concurrent Managers

Covers parallel ticket assignment, concurrent agent execution, shared agent pool, per-area concurrent managers, restructured orchestrator tick, merge queue ordering with parallel agents, resource management, plan branch locking, and concurrency model.

## Scope

- Default concurrency:
  - `concurrency.maxAgents` defaults to 4.
  - Gives new projects parallel execution out of the box without configuration.
  - Setting `maxAgents: 1` restores serial behavior.
  - All existing behavior preserved when `maxAgents` is 1.
- Shared agent pool with AgentRole enum:
  - Managers and coding agents share a single `maxAgents` slot pool, tracked in a shared `agent_pool` module.
  - `AgentRole` enum (`arCoder`, `arManager`) tags each agent slot.
  - `AgentSlot` gains a `role` field. Manager slots use `areaId` as identifier and have no branch or worktree — they produce ticket content in memory. Coder slots retain `ticketId`, `branch`, and `worktree`.
  - `startAgentAsync()` accepts a role and a generic worker proc.
  - `checkCompletedAgents()` returns completions tagged with role.
  - Slot arithmetic: if `maxAgents` is 4 and 2 managers are running, only 2 slots remain for coding agents (and vice versa).
  - Architect and review/merge remain strictly sequential and do not consume pool slots.
  - The orchestrator logs when an agent slot opens or fills.
- Per-area concurrent manager invocations:
  - Manager execution is per-area and concurrent: each eligible area spawns an independent manager agent thread using the `manager_tickets.md` single-area prompt template.
  - Manager agents generate ticket content in memory — they do not write to the plan worktree. Only the orchestrator main thread writes to the plan worktree.
  - Per-area manager flow:
    1. Orchestrator briefly acquires commit lock to snapshot area content for all areas needing tickets, then releases.
    2. For each area, if a slot is available in the shared pool, spawn a manager agent thread.
    3. Manager thread generates ticket documents in memory and sends results through the shared agent result channel.
    4. On the next tick, `checkCompletedAgents()` picks up manager completions.
    5. Main thread acquires commit lock, calls `writeTicketsForArea()` to persist tickets for one completed manager, commits, releases. Each completed manager's write is a separate short lock acquisition.
  - Eliminates concurrent write conflicts — agent threads never touch the plan worktree.
- Restructured orchestrator tick:
  - Managers and coders are interleaved rather than strictly sequential.
  - Tick order (detail in orchestrator area):
    1. Poll completed agents (managers + coders).
    2. Check health.
    3. Run architect (sequential, if spec changed).
    4. Read areas needing tickets (brief commit lock).
    5. For each area needing tickets, if slots available, start a manager agent (managers exempt from staggered start limit).
    6. For each assignable ticket, if slots available, start a coding agent (at most 1 new coding agent per tick — staggered start rule).
    7. Process at most one merge-queue item.
    8. Sleep.
  - Managers prioritized over coders when slots are scarce, since manager completions unblock future coding work.
  - When `maxAgents` is 1, behavior collapses to sequential execution as before.
- Narrow commit lock usage:
  - Reading areas: brief commit lock to snapshot area content at start of tick. Done once for all areas, not per-manager.
  - Agent execution: no lock needed. Manager agents run in threads and produce ticket content in memory.
  - Writing tickets: main thread acquires commit lock, writes tickets for one completed manager, commits, releases. Each completed manager's write is a separate lock acquisition — short and non-blocking.
  - Architect still holds commit lock for its full duration (reads spec and writes area files). Acceptable because architect is sequential and runs before managers are spawned.
- Parallel ticket assignment:
  - Orchestrator assigns multiple open tickets concurrently when they touch independent areas.
  - Independence determined by area: two tickets are independent if they reference different `**Area:** <area-id>` values.
  - Same-area tickets serialized — only one in-progress ticket per area at a time.
  - Staggered start rule: the orchestrator starts at most 1 new coding agent per tick to avoid burst-spawning. If multiple open tickets are assignable, one is started this tick and the rest wait for subsequent ticks.
  - Assignment order remains oldest-first: scan open tickets in ID order, assign each whose area is not already occupied.
  - Each assigned ticket gets its own worktree and branch (`scriptorium/ticket-<id>`).
- Concurrent agent execution:
  - Multiple coding agent processes run in parallel, one per assigned in-progress ticket.
  - Each agent runs in its own worktree with its own branch, fully isolated.
  - Orchestrator tracks all running agent processes and their associated ticket state.
  - Agent lifecycle (start, stall detection, continuation, submit_pr) applies independently to each running agent.
  - Orchestrator tick must not block on a single agent completing.
  - Log when agent slot opens or fills: `agent slots: <running>/<max> (ticket <id> started|finished)`.
- Merge queue ordering with parallel agents:
  - Multiple agents may call `submit_pr` independently, creating multiple pending merge queue entries.
  - Merge queue processing remains single-flight: at most one pending item per tick.
  - Pending items processed in submission order (FIFO by queue item ID).
  - Review agent flow applies to each merge queue item individually.
  - Failed merges do not affect other in-flight agents or pending queue items.
- Resource management:
  - Track aggregate `stdout_bytes` across all running agents as proxy for token consumption.
  - Token budget: optional `concurrency.tokenBudgetMB` in `scriptorium.json` (integer megabytes).
    - Pause new ticket assignment when cumulative session `stdout_bytes` exceeds budget.
    - Allow running agents to complete normally.
  - The orchestrator does not perform its own rate limit detection or backpressure. The coding harness (Claude Code, Codex) handles HTTP 429 retries internally.
- Concurrency model:
  - Strictly sequential agents: Architect (reads spec, writes areas, runs at most once per tick, protected by commit lock, must complete before managers) and Review/Merge (one merge queue item at a time, sequential to guarantee default branch health).
  - Parallel agents (shared slot pool): Manager (one area per invocation, multiple can run in parallel) and Coding agent (one ticket per invocation, multiple can run in parallel in independent areas). Both share the `maxAgents` slot pool.
  - Interleaved execution: managers and coders interleaved across ticks — orchestrator does not wait for all managers to finish before starting coders.
  - Merge conflict handling: parallel coding agents may produce merge conflicts on shared files. Sequential merge process catches conflicts by merging default branch into ticket branch before testing. Conflicting tickets sent back for another coding attempt with conflict context.
  - Slot arithmetic: if `maxAgents` is 4 and 2 managers are running, only 2 slots remain for coders (and vice versa).

## Known Limitations

- Conflict detection is area-level only — two tickets in different areas touching the same file are not detected until merge time.
- Token budget uses `stdout_bytes` as rough proxy — real token counts require harness-level API integration.
- Merge queue remains single-flight even with parallel agents — serialization point may bottleneck at high concurrency.

## Spec References

- Section 11: Parallel Ticket Assignment And Concurrency.
- Section 12: Resource Management.
- Section 17: Plan Branch Locking.
- Section 18: Concurrency Model.
