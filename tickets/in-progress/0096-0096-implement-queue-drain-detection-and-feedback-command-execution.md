# 0096 Implement queue-drain detection and feedback command execution

**Area:** loop-system

Add a new `src/scriptorium/loop_system.nim` module with queue-drain detection and feedback command execution.

## Requirements

### Queue-drain detection

1. Add `isQueueDrained*(planPath: string): bool` to `src/scriptorium/loop_system.nim`.

2. The queue is drained when **all three** conditions hold:
   - No markdown files in `tickets/open/`
   - No markdown files in `tickets/in-progress/`
   - No markdown files in `queue/merge/pending/` (excluding `.gitkeep`)

3. Use `listMarkdownFiles` from `ticket_metadata` to check each directory. Use `PlanTicketsOpenDir`, `PlanTicketsInProgressDir`, `PlanMergeQueuePendingDir` constants from `shared_state.nim`.

### Feedback command execution

4. Add `runFeedbackCommand*(repoPath: string, command: string): string`.

5. The proc should:
   - Run the command synchronously as a shell command in `repoPath` as the working directory.
   - Use `runCommandCapture` from `git_ops.nim`: call as `runCommandCapture(repoPath, "sh", @["-c", command])`.
   - Return stdout. If the command fails (non-zero exit), raise an exception with the exit code and output.
   - Use a 300_000 ms timeout.

### Unit tests

6. Add `tests/test_loop_system.nim` with tests:
   - `isQueueDrained` returns `true` when all directories are empty.
   - `isQueueDrained` returns `false` when any one directory has a `.md` file.
   - `runFeedbackCommand` with `echo hello` returns output containing `hello`.
   - `runFeedbackCommand` with a failing command (e.g., `exit 1`) raises.

## Implementation notes

- `listMarkdownFiles` is in `ticket_metadata.nim`.
- `runCommandCapture` is in `git_ops.nim` with signature `(workingDir, command, args, timeoutMs)`.
- Remember to add `config.nims` path hint: `tests/config.nims` already has `--path:"../src"`.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0096-0096-implement-queue-drain-detection-and-feedback-command-execution

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 11
- reasoning: Single new module with two straightforward procs plus unit tests, all using existing helpers with clear signatures specified in the ticket.
