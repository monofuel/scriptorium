# 0104 — Add pause flag helpers and wire into orchestrator

**Area:** discord

## Description

Implement pause flag file management in `.scriptorium/` and make the orchestrator respect it. The pause flag is a simple file presence check — when `.scriptorium/pause` exists, the orchestrator stops picking up new work but lets in-flight agents finish.

### Requirements

1. Add procs to a suitable module (e.g. `src/scriptorium/shared_state.nim` or a new `src/scriptorium/pause_flag.nim`):
   - `writePauseFlag*(repoPath: string)` — Create `.scriptorium/pause` file. Idempotent.
   - `removePauseFlag*(repoPath: string)` — Remove `.scriptorium/pause` file. Idempotent (no error if missing).
   - `isPaused*(repoPath: string): bool` — Return `true` when `.scriptorium/pause` exists.

   Use `ManagedStateDirName` constant (`.scriptorium`) from `git_ops.nim` for the directory path.

2. In `src/scriptorium/orchestrator.nim`, check `isPaused(repoPath)` at the top of the tick loop (before assigning new work). When paused:
   - Log a message: `"orchestrator paused, skipping new assignments"`
   - Skip ticket assignment and manager spawning for this tick.
   - Continue processing the merge queue and in-flight agent completions (do not halt everything).

3. Add unit tests verifying:
   - `writePauseFlag` creates the file, `isPaused` returns true.
   - `removePauseFlag` removes the file, `isPaused` returns false.
   - `removePauseFlag` on a non-existent file does not raise.
   - `writePauseFlag` called twice does not raise.

### Notes

- The pause file contents don't matter — file presence is the signal. Write an empty file or a timestamp.
- Import `os` for `fileExists`, `writeFile`, `removeFile`.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0106-0104-add-pause-flag-helpers-and-wire-into-orchestrator
