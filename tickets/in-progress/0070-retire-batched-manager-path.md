# Retire Batched Manager Path

**Area:** parallel-execution

**Depends:** 0069

## Problem

V13 §32 requires removing the batched manager execution model now that per-area concurrent managers are implemented.

## Requirements

1. Remove `proc runManagerTickets*()` from `manager_agent.nim`.
2. Remove `proc syncTicketsFromAreas*()` from `manager_agent.nim` (if it exists).
3. Remove `ManagerTicketsBatchTemplate` export from `prompt_catalog.nim`.
4. Remove `proc buildManagerTicketsBatchPrompt*()` from `prompt_builders.nim`.
5. Delete the `src/scriptorium/prompts/manager_tickets_batch.md` prompt template file.
6. Update `orchestrator.nim` to remove calls to the batched manager path (the `runManagerTickets` call in the tick loop).
7. Update or remove unit tests that reference removed functions and templates.
8. `make test` must pass after all removals.

## Notes

- The production manager path after this ticket is the per-area concurrent model from ticket 0069.
- The single-area `manager_tickets.md` template and `ManagerTicketsTemplate` must be preserved.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0070-retire-batched-manager-path

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Straightforward deletion of well-enumerated functions, a template file, and their references across ~5 files with no new logic to write — just removals and test cleanup, one attempt expected.

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Straightforward deletion of well-enumerated functions, a template file, and their references across ~5 files with no new logic to write — just removals and test cleanup, one attempt expected.
