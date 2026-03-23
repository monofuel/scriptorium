# Add unit test for manager priority over coders

**Area:** parallel-execution

## Task

Add a test to `tests/test_orchestrator_flow.nim` in the
`"concurrent agent execution"` suite that verifies managers are prioritized
over coding agents when slots are scarce.

### Test design

1. Create a test repo with `maxAgents: 2`.
2. Write a spec and configure it so the architect produces 2 areas that both
   need tickets.
3. Add 1 open ticket in area-a so a coding agent is also eligible.
4. Use a fake runner that tracks the order of agent invocations by `ticketId`:
   - Architect: writes 2 area files.
   - Manager agents: return ticket documents.
   - Coding agent: calls `recordSubmitPrSummary`.
5. Run `runOrchestratorForTicks(tmp, 4, fakeRunner)`.
6. Assert that in the tick where both a manager and a coding agent are
   eligible, the manager starts first (i.e., manager `ticketId` entries appear
   before the coding agent `ticketId` in the call order for that tick).

This validates the tick order guarantee: step 5 (managers) runs before step 6
(coders).

Run `make test` to verify the new test passes.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0091-add-unit-test-for-manager-priority-over-coders
