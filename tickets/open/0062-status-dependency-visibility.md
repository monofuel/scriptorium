# Dependency Visibility In Status Command

**Area:** status-worktrees
**Depends:** 0058

## Problem

V7 §29 requires that `scriptorium status` reports tickets blocked by circular dependencies and tickets waiting on unsatisfied dependencies. Currently, the status command has no dependency awareness.

## Requirements

### Circular dependency reporting
- When tickets are blocked by circular dependencies, status must report: `Blocked: <id> (circular dependency with <id-list>)`.
- Use the cycle detection logic from ticket 0058.

### Unsatisfied dependency reporting
- When tickets are blocked by unsatisfied (but non-circular) dependencies, status must report: `Waiting: <id> (depends on <id-list>)`.
- Show only open tickets whose dependencies are not yet in `tickets/done/`.

### Integration with readOrchestratorStatus
- Extend `OrchestratorStatus` to include blocked and waiting ticket information.
- Parse dependency fields from open tickets on the plan branch.
- Run cycle detection on the dependency graph.

## Acceptance Criteria

- `scriptorium status` shows `Blocked:` lines for circular dependency tickets.
- Shows `Waiting:` lines for tickets with unsatisfied dependencies.
- Uses cycle detection from ticket 0058.
- Existing status output unchanged.
- `make test` passes with tests covering both blocked and waiting output.
