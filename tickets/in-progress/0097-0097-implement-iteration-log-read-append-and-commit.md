# 0097 Implement iteration log read, append, and commit

**Area:** loop-system

Add procs to manage `iteration_log.md` on the plan branch.

## Requirements

1. Add to `src/scriptorium/loop_system.nim`:
   - `const IterationLogPath* = "iteration_log.md"`
   - `readIterationLog*(planPath: string): string` — reads the file content, returns `""` if missing.
   - `appendIterationLogEntry*(planPath: string, iteration: int, feedbackOutput: string, assessment: string, strategy: string, tradeoffs: string)` — appends a formatted entry to the file.
   - `nextIterationNumber*(planPath: string): int` — parses the log to find the highest `## Iteration N` heading and returns N+1. Returns 1 if no entries exist.
   - `commitIterationLog*(planPath: string)` — stages and commits `iteration_log.md` if changed.

2. Entry format (append to file):

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0097-0097-implement-iteration-log-read-append-and-commit

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Single-file additions to loop_system.nim with file I/O, string parsing for iteration numbers, and git commit logic, plus corresponding unit tests — moderate complexity but contained to one module.
