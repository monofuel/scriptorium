# Loop System

Covers the feedback loop mode where the orchestrator re-invokes the architect after all work drains, using external feedback to guide iterative improvement.

## Scope

- When `loop.enabled` is true in `scriptorium.json`, the orchestrator enters loop mode. Instead of stopping when all work is done, it runs a feedback cycle and hands the results to the architect for the next iteration.

### Queue-Drain Detection

- The queue is considered drained when all three conditions hold: no open tickets, no in-progress tickets, and no pending merge queue items.
- Queue-drain detection runs as step 8 of the tick order (after merge queue processing, before sleep).
- When drain is detected and `loop.enabled` is true, the orchestrator initiates the feedback cycle instead of idling.
- If `loop.maxIterations` is non-zero and the current iteration count has reached the limit, the orchestrator stops instead of initiating another cycle.

### Feedback Cycle

1. **Run feedback command:** Execute the shell command in `loop.feedback` in the repository root. Capture its stdout as the feedback output. The command runs synchronously — the orchestrator waits for it to complete.
2. **Invoke the architect:** Pass the architect a prompt containing:
   - The `loop.goal` string.
   - The full contents of `iteration_log.md` from the plan branch.
   - The feedback output from step 1.
3. **Architect writes iteration log entry:** The architect appends a new entry to `iteration_log.md` with: iteration number, feedback output summary, assessment of previous results, strategy for the next iteration, and acceptable tradeoffs.
4. **Architect creates/updates areas and tickets:** The architect updates `spec.md`, areas, or creates tickets for the next iteration as part of the same invocation. Normal area-generation and manager ticket-generation flows then produce work for the next cycle.
5. **Cycle repeats:** The orchestrator returns to normal tick processing. When the queue drains again, the feedback cycle runs again.

### Iteration Log

- `iteration_log.md` lives on the plan branch alongside `spec.md`.
- It is append-only. Each entry records:
  - Iteration number (monotonically increasing, starting at 1).
  - Feedback output (the stdout of the feedback command).
  - Assessment of previous iteration results.
  - Strategy for the next iteration.
  - Acceptable tradeoffs declared by the architect.
- The architect reads the full log before planning each iteration. This is the architect's memory across iterations.
- After the architect writes a new entry and any spec/area changes, the orchestrator commits `iteration_log.md` to the plan branch under the commit lock.

### Soft Gating Via Architect Judgment

- The architect declares expected tradeoffs in each iteration log entry. After the next feedback step, the architect reviews actual results against declared expectations.
- If results are within declared tolerance, the architect continues with the next optimization.
- If results diverge significantly from expectations, the architect's next iteration should investigate what went wrong rather than pressing forward.
- For hard constraints, the architect encodes them in its strategy and treats violations as non-negotiable.
- All gating is architect judgment — no structured metric parsing, no numeric thresholds, no automatic rollback.

### MVP Scope

The loop system is deliberately minimal. It does not include: A/B branching, automatic rollback, structured metric parsing, special review agent behavior, or manager-level gating. The entire loop surface is: feedback command + iteration log + architect judgment.

## Spec References

- Section 22: Loop System.
- Section 3: Orchestrator Run Loop (tick step 8, queue drain detection).
- Section 16: Config, Logging, And CI (loop config keys).
- Section 4: Planning Artifacts And State Model (iteration_log.md in plan branch layout).
