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
