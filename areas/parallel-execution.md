# Multi-Ticket Parallelism

Covers parallel ticket assignment, concurrent agent execution, merge queue ordering with parallel agents, and resource management.

## Scope

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
  - Concurrency limit configurable via `scriptorium.json` under `concurrency.maxAgents` (integer, default 1).
  - Value of 1 preserves existing serial behavior; recommended parallel starting value is 2-3.
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

## V5 Known Limitations

- Conflict detection is area-level only — two tickets in different areas touching the same file are not detected until merge time.
- Speculative execution (starting potentially conflicting tickets) is out of scope.
- Dynamic concurrency scaling based on v3 metrics is out of scope — concurrency limit is static per session.
- Token budget uses `stdout_bytes` as rough proxy — real token counts require harness-level API integration.
- Rate limit detection depends on harness-specific error reporting — not all backends may surface 429s uniformly.
- Merge queue remains single-flight even with parallel agents — serialization point may bottleneck at high concurrency.

## Spec References

- Section 23: Parallel Ticket Assignment.
- Section 24: Concurrent Agent Execution.
- Section 25: Merge Queue Ordering With Parallel Agents.
- Section 26: Resource Management.
