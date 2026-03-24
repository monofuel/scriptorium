# 0098 Build architect loop prompt and invoke architect for feedback cycle

**Area:** loop-system

Add the prompt builder and invocation proc that passes loop context to the architect.

## Requirements

1. Add `buildArchitectLoopPrompt*(repoPath: string, planPath: string, goal: string, iterationLog: string, feedbackOutput: string, iterationNumber: int): string` to `src/scriptorium/prompt_builders.nim`.

2. The prompt should contain:
   - The `goal` string.
   - The full `iteration_log.md` contents (the architect's memory across iterations).
   - The feedback output from the latest feedback command.
   - The current iteration number.
   - Instructions telling the architect to:
     - Assess previous results against declared expectations from the prior iteration.
     - Write the next iteration log entry to `iteration_log.md` (iteration number, feedback summary, assessment, strategy, tradeoffs).
     - Update `spec.md`, area files, or create tickets as needed for the next iteration.
     - If results diverge significantly from prior declared expectations, investigate rather than press forward.
     - For hard constraints, treat violations as non-negotiable.

3. Add `runArchitectLoopIteration*(repoPath: string, runner: AgentRunner, feedbackOutput: string): bool` to `src/scriptorium/loop_system.nim`.

   This proc should:
   - Load config to get `loop.goal`.
   - Open a locked plan worktree (`withLockedPlanWorktree` from `lock_management.nim`).
   - Read the existing iteration log with `readIterationLog`.
   - Compute the next iteration number with `nextIterationNumber`.
   - Build the prompt using `buildArchitectLoopPrompt`.
   - Invoke the architect via `runPlanArchitectRequest` (from `architect_agent.nim`), allowing writes to `spec.md`, `areas/`, `tickets/open/`, and `iteration_log.md`.
   - After the architect runs, if it didn't write the iteration log entry (check via `nextIterationNumber` again), append a fallback entry with the feedback output and placeholder assessment/strategy text.
   - Commit the iteration log with `commitIterationLog`.
   - Update the spec hash marker with `writeSpecHashMarker` if spec changed.
   - Return `true` if the architect produced changes.

4. Add a unit test with a mock runner that verifies the prompt contains goal, iteration log content, and feedback output.

## Depends: 0097

## Implementation notes

- Use `runPlanArchitectRequest` from `architect_agent.nim` for the architect invocation.
- Use `withLockedPlanWorktree` from `lock_management.nim` for plan branch access.
- The architect agent config comes from `loadConfig(repoPath).agents.architect`.
- The write allowlist for `enforceWritePrefixAllowlist` should include: `spec.md`, `areas`, `tickets/open`, `iteration_log.md`.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0098-0098-build-architect-loop-prompt-and-invoke-architect-for-feedback-cycle
