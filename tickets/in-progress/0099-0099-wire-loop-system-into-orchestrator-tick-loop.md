# 0099 Wire loop system into orchestrator tick loop

**Area:** loop-system

Integrate queue-drain detection and feedback cycle into the orchestrator as tick step 8.

## Requirements

1. In `src/scriptorium/orchestrator.nim`, add the loop system import (`./loop_system`).

2. Add loop iteration state to `runOrchestratorMainLoop`:
   - `var loopIterationCount = 0` — tracks how many feedback cycles have run this session.
   - Load `cfg.loop` at the start alongside `maxAgents`.

3. After step 7 (merge queue processing, around line 330) and before the idle/sleep decision, add step 8:
   - Only if `cfg.loop.enabled` is `true` and `cfg.loop.feedback.len > 0`:
     - Check queue drain: `withPlanWorktree(repoPath, proc(planPath: string): bool = isQueueDrained(planPath))`
     - Also check `runningAgentCount() == 0` (no async agents still running).
     - If drained:
       - If `cfg.loop.maxIterations > 0` and `loopIterationCount >= cfg.loop.maxIterations`:
         - Log `"loop: max iterations reached ({loopIterationCount}/{cfg.loop.maxIterations})"` at INFO level.
         - Do not start another cycle.
       - Otherwise:
         - Increment `loopIterationCount`.
         - Log: `"loop: queue drained, starting feedback cycle (iteration {loopIterationCount})"` at INFO.
         - Call `runFeedbackCommand(repoPath, cfg.loop.feedback)` to get feedback output.
         - Call `runArchitectLoopIteration(repoPath, runner, feedbackOutput)`.
         - Log: `"loop: feedback cycle {loopIterationCount} complete"` at INFO.
         - Set `idle = false` so the orchestrator immediately processes the next tick.

4. Add `loop={loopIterationCount}` to the tick summary log line (the `summary` string near line 339).

5. Add a unit test in `tests/test_orchestrator_flow.nim` (or `tests/test_loop_system.nim`) using a fake runner that verifies:
   - When `loop.enabled = false`, no feedback cycle runs even when queue is drained.
   - When `loop.enabled = true` and queue is drained, the feedback command and architect are invoked.
   - When `maxIterations` is reached, no further cycles run.

## Depends: 0095, 0096, 0098

## Implementation notes

- The orchestrator already uses `withPlanWorktree` extensively — follow the same pattern for drain checks.
- Keep the loop logic minimal in the orchestrator: just detection + invocation. All intelligence lives in the architect prompt and judgment.
- If the feedback command fails, log the error and skip the cycle (don't crash the orchestrator). Use a try/except around the feedback+architect calls, logging the error at WARN level.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0099-0099-wire-loop-system-into-orchestrator-tick-loop
