# Add unit test for staggered coding agent start

**Area:** parallel-execution
**Depends:** 0089

## Task

Add a test to `tests/test_orchestrator_flow.nim` in the
`"concurrent agent execution"` suite that verifies the staggered start rule:
only 1 new coding agent starts per orchestrator tick.

### Test design

1. Create a test repo with 3 open tickets in different areas (area-a, area-b,
   area-c) and set `maxAgents: 4`.
2. Use a fake runner that:
   - Handles architect and manager calls as no-ops.
   - For coding agents: records the tick on which each ticket's coding call
     occurs (use a shared counter incremented per tick by counting
     `runOrchestratorForTicks` calls).
   - Calls `recordSubmitPrSummary` immediately so tickets complete in one
     coding call.
3. Run `runOrchestratorForTicks(tmp, 5, fakeRunner)`.
4. Assert that coding agents for the 3 tickets were started on 3 different
   ticks (not all on the same tick).

Use the existing `helpers` module and test patterns from the file. The test
helper `addTicketToPlan`, `addPassingMakefile`, and `writeScriptoriumConfig`
are already available.

Run `make test` to verify the new test passes.
