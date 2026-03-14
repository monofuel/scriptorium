# Ticket Dependency Cycle Detection

**Area:** plan-state

## Problem

The orchestrator has `dependenciesSatisfied` for linear dependency checking, but V7 §29 requires detecting circular dependencies in the ticket graph. Currently, a cycle (A depends on B, B depends on A) would cause both tickets to be permanently blocked with no warning.

## Requirements

### Cycle detection algorithm
- After the manager writes new tickets, validate the dependency graph remains acyclic.
- Build a directed graph from all open and in-progress tickets using `**Depends:** <id-list>` fields.
- Implement cycle detection using Tarjan's algorithm or DFS-based strongly connected component detection.
- If a cycle is detected, log error: `ticket <id>: dependency cycle detected (<id> -> <id> -> ... -> <id>)`.

### Periodic scan
- On each tick, scan open and in-progress tickets to identify tickets permanently blocked by cycles.
- Log warnings for tickets blocked by cycles.
- The existing `dependenciesSatisfied` proc continues to work as before for non-circular dependencies.

### Unit tests
- Simple cycle: A depends on B, B depends on A.
- Multi-node cycle: A depends on B, B depends on C, C depends on A.
- No cycle: A depends on B, B depends on C (linear chain).
- Self-dependency: A depends on A.
- Mixed graph: some tickets in cycles, others not — only cyclic tickets flagged.

## Acceptance Criteria

- Cycle detection runs after manager ticket generation.
- Cycles logged as errors with the full cycle path.
- Periodic tick scan warns about blocked tickets.
- `dependenciesSatisfied` unchanged for non-circular cases.
- `make test` passes with all new cycle detection tests.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0058-dependency-cycle-detection

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Graph cycle detection is a well-defined algorithm (DFS/Tarjan's) added to existing dependency logic, touching 1-2 modules plus a new test file, with moderate complexity from graph building and path reporting but low integration risk since dependenciesSatisfied is unchanged.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0058-dependency-cycle-detection/.scriptorium/logs/0058/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0058-dependency-cycle-detection/.scriptorium/logs/0058/attempt-01.last_message.txt\n
### Agent Last Message
```text
The PR has been submitted successfully. The orchestrator responded with "Merge request enqueued."

Here's a summary of what was implemented:

**New file: `src/scriptorium/cycle_detection.nim`**
- `buildDependencyGraph` - builds a directed graph from open/in-progress tickets' `**Depends:**` fields
- `detectCycles` - DFS-based cycle detection returning all cycle paths
- `detectAndLogCycles` - logs errors with full cycle paths after manager generates tickets
- `scanForCycleBlockedTickets` - logs warnings for tickets permanently blocked by cycles

**Modified: `src/scriptorium/orchestrator.nim`**
- Runs `detectAndLogCycles` after manager creates new tickets
- Runs `scanForCycleBlockedTickets` on each tick
- `dependenciesSatisfied` remains unchanged

**New file: `tests/test_cycle_detection.nim`** - 7 tests:
- Simple cycle (A↔B), multi-node cycle (A→B→C→A), no cycle (linear chain), self-dependency (A→A), mixed graph (only cyclic flagged), empty graph, dependency to non-existent ticket
```

### Agent Stdout Tail
```text
cle (A↔B), multi-node cycle (A→B→C→A), no cycle (linear chain), self-dependency (A→A), mixed graph (only cyclic flagged), empty graph, dependency to non-existent ticket","stop_reason":"end_turn","session_id":"d8b18897-93c4-4c04-bd5b-668f2c3c440e","total_cost_usd":2.063333699999999,"usage":{"input_tokens":61,"cache_creation_input_tokens":50009,"cache_read_input_tokens":2648420,"output_tokens":11481,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":50009,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":61,"outputTokens":11481,"cacheReadInputTokens":2648420,"cacheCreationInputTokens":50009,"webSearchRequests":0,"costUSD":1.9240962499999992,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":44,"outputTokens":7508,"cacheReadInputTokens":386872,"cacheCreationInputTokens":50373,"webSearchRequests":0,"costUSD":0.13923744999999998,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"dae13420-925e-4f8f-b52c-5176560cdad9"}
```
