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

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 1m53s

## Merge Queue Success
- Summary: Add dependency cycle detection for ticket graph using DFS-based algorithm. Detects cycles after manager ticket generation and on each tick scan. Includes 7 unit tests covering simple cycles, multi-node cycles, self-dependencies, mixed graphs, and acyclic cases.\n
### Quality Check Output
```text
ping tick
[2026-03-14T00:35:25Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=2 tickets_reopened=3 tickets_parked=0 merge_queue_processed=2
[2026-03-14T00:35:25Z] [INFO] session summary: avg_ticket_wall=0s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
[2026-03-14T00:35:25Z] [INFO] architect: generating areas from spec
[2026-03-14T00:35:26Z] [INFO] architect: areas updated
[2026-03-14T00:35:26Z] [INFO] manager: generating tickets
[2026-03-14T00:35:26Z] [INFO] merge queue: processing
[2026-03-14T00:35:26Z] [INFO] ticket 0001: review started (model=codex-fake-unit-test-model)
[2026-03-14T00:35:26Z] [WARN] ticket 0001: review agent stalled, defaulting to approve
[2026-03-14T00:35:26Z] [INFO] ticket 0001: merge started (make test running)
[2026-03-14T00:35:26Z] [INFO] ticket 0001: merge succeeded (test wall=0s)
[2026-03-14T00:35:26Z] [INFO] ticket 0001: in-progress -> done (total wall=31s, attempts=0)
[2026-03-14T00:35:26Z] [INFO] ticket 0001: post-analysis skipped (no prediction section)
[2026-03-14T00:35:26Z] [INFO] merge queue: item processed
[2026-03-14T00:35:26Z] [INFO] tick 0 summary: architect=updated manager=no-op coding=idle merge=processing open=0 in-progress=0 done=1
[2026-03-14T00:35:27Z] [INFO] session summary: uptime=1s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-14T00:35:27Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-10 global halt while red resumes after master health is restored
[2026-03-14T00:35:27Z] [WARN] master is unhealthy — skipping tick
[2026-03-14T00:35:57Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-14T00:35:57Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-11 integration-test failure on master blocks assignment of open tickets
```

## Metrics
- wall_time_seconds: 933
- coding_wall_seconds: 534
- test_wall_seconds: 274
- attempt_count: 1
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 533875

## Post-Analysis
- actual_difficulty: medium
- prediction_accuracy: accurate
- brief_summary: Predicted medium, actual was medium with 1 attempt(s) in 15m33s.
