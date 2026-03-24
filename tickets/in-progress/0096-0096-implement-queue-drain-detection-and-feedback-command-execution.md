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

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0096/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0096/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Added `src/scriptorium/loop_system.nim` with two procs:

- **`isQueueDrained`** — returns `true` when `tickets/open/`, `tickets/in-progress/`, and `queue/merge/pending/` have no markdown files
- **`runFeedbackCommand`** — runs a shell command via `runCommandCapture` with 300s timeout, returns stdout or raises on failure

All 6 unit tests in `tests/test_loop_system.nim` pass. PR submitted.
```

### Agent Stdout Tail
```text
ult":"Done. Added `src/scriptorium/loop_system.nim` with two procs:\n\n- **`isQueueDrained`** — returns `true` when `tickets/open/`, `tickets/in-progress/`, and `queue/merge/pending/` have no markdown files\n- **`runFeedbackCommand`** — runs a shell command via `runCommandCapture` with 300s timeout, returns stdout or raises on failure\n\nAll 6 unit tests in `tests/test_loop_system.nim` pass. PR submitted.","stop_reason":"end_turn","session_id":"167acf46-a095-4a67-a1dc-d439630e04b9","total_cost_usd":0.3976595,"usage":{"input_tokens":16,"cache_creation_input_tokens":30572,"cache_read_input_tokens":249909,"output_tokens":3262,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":30572},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":16,"outputTokens":3262,"cacheReadInputTokens":249909,"cacheCreationInputTokens":30572,"webSearchRequests":0,"costUSD":0.3976595,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"58349064-c4a2-4e22-8c82-a48bb0a5b5fe"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 35s

**Review Reasoning:** I'll review the changes against the ticket requirements and project conventions.
Let me check the relevant source files to verify the implementation.
Now let me read the actual new files to verify them in full context.
Implementation looks clean. Let me check one thing — `os` is imported in `loop_system.nim` but I want to confirm it's used (for the `/` operator).

The `/` path join operator comes from `std/os`, so that import is used. `strformat` is used for the `&` operator. `git_ops`, `shared_state`, and `ticket_metadata` are all used.

Let me check the `strutils` import in tests — it's used for `strip()`. Good.

**Review summary:**

- **Imports**: Correct style — single block, bracket syntax, std/ first then local. No unused imports.
- **Naming**: PascalCase constants, camelCase variables — all correct.
- **Doc comments**: Both procs have `##` doc comments with complete sentences and punctuation.
- **Variable grouping**: `let` block used properly in `isQueueDrained`.
- **Error handling**: Exception raised on failure (not boolean), `&` used for format strings with variables pre-assigned on lines 17-18.
- **Spec compliance**: `isQueueDrained` checks all three directories using the correct constants and `listMarkdownFiles`. `runFeedbackCommand` uses `runCommandCapture` with `sh -c`, 300_000ms timeout, returns stdout, raises on non-zero exit.
- **Tests**: All 6 required test cases present — empty dirs true, each dir false (3 tests), echo success, exit 1 failure.
- **No dead code, no unrelated changes, no leftover artifacts.**

One minor note: `strutils` is imported in the test file but not in the source — that's fine since it's only used in tests for `strip()`.
**Approved.** Clean implementation that matches all ticket requirements and project conventions. Both procs are correct, imports are minimal and used, error handling follows the project pattern (raise on failure, no boolean returns), and all 6 required test cases are present.
