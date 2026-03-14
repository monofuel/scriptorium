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
