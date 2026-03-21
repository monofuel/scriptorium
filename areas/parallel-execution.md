# Multi-Ticket Parallelism And Concurrent Managers

Covers parallel ticket assignment, concurrent agent execution, shared agent pool, per-area concurrent managers, restructured orchestrator tick, merge queue ordering with parallel agents, resource management, and concurrency model documentation.

## Scope

- Default concurrency (V13, §27):
  - `concurrency.maxAgents` defaults to 4 (changed from 1 in V13).
  - Gives new projects parallel execution out of the box without configuration.
  - Setting `maxAgents: 1` restores serial behavior.
  - All existing behavior preserved when `maxAgents` is 1.
- Shared agent pool with AgentRole enum (V13, §28):
  - Managers and coding agents share a single `maxAgents` slot pool, tracked in a shared `agent_pool` module extracted from `coding_agent.nim`.
  - `AgentRole` enum (`arCoder`, `arManager`) tags each agent slot.
  - `AgentSlot` gains a `role` field. Manager slots use `areaId` as identifier and have no branch or worktree — they produce ticket content in memory. Coder slots retain `ticketId`, `branch`, and `worktree`.
  - `AgentCompletionResult` gains a `role` field and an optional `managerResult` (list of generated ticket documents) alongside existing coding result fields.
  - `startAgentAsync()` accepts a role and a generic worker proc. Coding agents pass `executeAssignedTicket` wrapper; manager agents pass `executeManagerForArea` wrapper.
  - `checkCompletedAgents()` returns completions tagged with role for orchestrator dispatch.
  - Slot arithmetic: if `maxAgents` is 4 and 2 managers are running, only 2 slots remain for coding agents (and vice versa).
  - Architect and review/merge remain strictly sequential and do not consume pool slots.
- Per-area concurrent manager invocations (V13, §29):
  - The batched manager execution model (single agent prompt containing all areas) is retired.
  - Manager execution is per-area and concurrent: each eligible area spawns an independent manager agent thread using the `manager_tickets.md` single-area prompt template.
  - Manager agents generate ticket content in memory — they do not write to the plan worktree. Only the orchestrator main thread writes to the plan worktree.
  - Per-area manager flow:
    1. Orchestrator briefly acquires plan lock to snapshot area content for all areas needing tickets, then releases.
    2. For each area, if a slot is available in the shared pool, spawn a manager agent thread.
    3. Manager thread generates ticket documents in memory and sends results through the shared agent result channel.
    4. On the next tick, `checkCompletedAgents()` picks up manager completions.
    5. Main thread acquires plan lock, calls `writeTicketsForArea()` to persist tickets for one completed manager, commits, releases. Each completed manager's write is a separate short lock acquisition.
  - Eliminates concurrent write conflicts — agent threads never touch the plan worktree.
- Restructured orchestrator tick (V13, §30):
  - Managers and coders are interleaved rather than strictly sequential.
  - New tick order:
    1. Poll completed agents (managers + coders) via `checkCompletedAgents()`.
       - For completed managers: acquire plan lock, write tickets, commit, release. Log results.
       - For completed coders: handle as before (move ticket, queue merge, etc).
    2. Check backoff / health.
    3. Run architect (sequential, if spec changed). Must complete before managers are spawned.
    4. Read areas needing tickets (brief plan lock).
    5. For each area needing tickets, if slots available, start a manager agent.
    6. For each assignable ticket, if slots available, start a coding agent.
    7. Process at most one merge-queue item.
    8. Sleep.
  - Managers prioritized over coders when slots are scarce, since manager completions unblock future coding work.
  - If area A's manager finishes and produces tickets while area B's manager is still running, those tickets can be assigned to coding agents on the next tick — no barrier between manager and coder phases.
  - When `maxAgents` is 1, behavior collapses to sequential execution as before.
- Narrow plan branch locking (V13, §31):
  - Reading areas: brief lock to snapshot area content at start of tick. Done once for all areas, not per-manager.
  - Agent execution: no lock needed. Manager agents run in threads and produce ticket content in memory.
  - Writing tickets: main thread acquires lock, writes tickets for one completed manager, commits, releases. Each completed manager's write is a separate lock acquisition — short and non-blocking.
  - Architect still holds lock for its full duration (reads spec and writes area files). Acceptable because architect is sequential and runs before managers are spawned.
  - Replaces previous model where lock was held for entire manager batch execution.
- Retirement of batched manager path (V13, §32):
  - Removed: `runManagerTickets()`, `syncTicketsFromAreas()`, `manager_tickets_batch.md`, `ManagerTicketsBatchTemplate` export from `prompt_catalog.nim`, `buildManagerTicketsBatchPrompt` from `prompt_builders.nim`.
  - Production manager path is now the per-area concurrent model using `manager_tickets.md`.
  - Tests referencing removed functions and templates must be updated or removed.
- Parallel ticket assignment (V5, §23):
  - Orchestrator assigns multiple open tickets concurrently when they touch independent areas.
  - Independence determined by area: two tickets are independent if they reference different `**Area:** <area-id>` values.
  - Same-area tickets serialized — only one in-progress ticket per area at a time.
  - Up to N tickets assigned per tick, where N is the configured concurrency limit.
  - Assignment order remains oldest-first: scan open tickets in ID order, assign each whose area is not already occupied.
  - Each assigned ticket gets its own worktree and branch (`scriptorium/ticket-<id>`).
  - Replaces single-ticket assignment path (§4) but behavior identical when concurrency is 1.
- Concurrent agent execution (V5, §24):
  - Multiple coding agent processes run in parallel, one per assigned in-progress ticket.
  - Each agent runs in its own worktree with its own branch, fully isolated.
  - Orchestrator tracks all running agent processes and their associated ticket state.
  - Agent lifecycle (start, stall detection, continuation, submit_pr) applies independently to each running agent.
  - Orchestrator tick must not block on a single agent completing — it must:
    - Check for newly completable agents (exited processes).
    - Start new agents for newly assigned tickets.
    - Continue processing other tick phases (architect, manager, merge queue) while agents run.
  - Concurrency limit configurable via `scriptorium.json` under `concurrency.maxAgents` (integer, default 4 — changed from 1 in V13).
  - Value of 1 restores serial behavior.
  - Log when agent slot opens or fills: `agent slots: <running>/<max> (ticket <id> started|finished)`.
- Merge queue ordering with parallel agents (V5, §25):
  - Multiple agents may call `submit_pr` independently, creating multiple pending merge queue entries.
  - Merge queue processing remains single-flight: at most one pending item per tick (§7).
  - Pending items processed in submission order (FIFO by queue item ID).
  - Review agent flow (§21) applies to each merge queue item individually.
  - Failed merges do not affect other in-flight agents or pending queue items.
  - After successful merge changes `master`, all other in-progress ticket worktrees merge `master` into their branch before next `submit_pr` pre-check or merge queue processing (handled by existing merge queue logic in §7).
- Resource management (V5, §26):
  - Monitor and respect API rate limits and token budgets across all parallel agents.
  - Backpressure: delay new agent starts when approaching rate limits rather than failing running agents.
  - Track aggregate `stdout_bytes` across all running agents as proxy for token consumption.
  - Token budget: optional `concurrency.tokenBudgetMB` in `scriptorium.json` (integer megabytes).
    - Pause new ticket assignment when cumulative session `stdout_bytes` exceeds budget.
    - Log warning: `resource limit: token budget exhausted (<used>MB/<budget>MB), pausing new assignments`.
    - Allow running agents to complete normally.
  - Rate limit detection: if agent harness returns HTTP 429 or equivalent:
    - Log: `resource limit: rate limited (ticket <id>, backing off <n>s)`.
    - Apply exponential backoff before starting new agents (not before retrying the failed agent).
    - Reduce effective concurrency by 1 temporarily until backoff period expires.
- Concurrency model documentation (V13, §33):
  - Strictly sequential agents: Architect (reads spec, writes areas, runs at most once per tick, protected by plan lock, must complete before managers) and Review/Merge (one merge queue item at a time, sequential to guarantee default branch health).
  - Parallel agents (shared slot pool): Manager (one area per invocation, multiple can run in parallel) and Coding agent (one ticket per invocation, multiple can run in parallel in independent areas). Both share the `maxAgents` slot pool.
  - Interleaved execution: managers and coders interleaved across ticks — orchestrator does not wait for all managers to finish before starting coders.
  - Merge conflict handling: parallel coding agents may produce merge conflicts on shared files. Sequential merge process catches conflicts by merging default branch into ticket branch before testing. Conflicting tickets sent back for another coding attempt with conflict context. Area-based separation makes conflicts less likely but system handles them gracefully.
  - Slot arithmetic: if `maxAgents` is 4 and 2 managers are running, only 2 slots remain for coders (and vice versa).

## Known Limitations

- Conflict detection is area-level only — two tickets in different areas touching the same file are not detected until merge time.
- Speculative execution (starting potentially conflicting tickets) is out of scope.
- Dynamic concurrency scaling based on v3 metrics is out of scope — concurrency limit is static per session.
- Token budget uses `stdout_bytes` as rough proxy — real token counts require harness-level API integration.
- Rate limit detection depends on harness-specific error reporting — not all backends may surface 429s uniformly.
- Merge queue remains single-flight even with parallel agents — serialization point may bottleneck at high concurrency.
- Manager parallelism is bounded by `maxAgents` — if all slots are occupied by coding agents, managers must wait for a slot to free up.
- Shared slot pool does not distinguish between lightweight manager invocations and heavyweight coding agent sessions — future version could weight slots by expected resource usage.
- Area-level conflict detection remains the only conflict prevention mechanism (same as V5).

## Spec References

- Section 23: Parallel Ticket Assignment (V5).
- Section 24: Concurrent Agent Execution (V5).
- Section 25: Merge Queue Ordering With Parallel Agents (V5).
- Section 26: Resource Management (V5).
- Section 27: Default maxAgents Changed To 4 (V13).
- Section 28: Shared Agent Pool With AgentRole Enum (V13).
- Section 29: Per-Area Concurrent Manager Invocations (V13).
- Section 30: Restructured Orchestrator Tick For Interleaved Manager/Coder Execution (V13).
- Section 31: Narrow Plan Branch Locking (V13).
- Section 32: Retirement Of Batched Manager Path (V13).
- Section 33: Concurrency Model Documentation (V13).
