# Use git worktree remove in recovery orphan reopening

**Area:** plan-state

## Problem

In `src/scriptorium/recovery.nim:274`, `reopenOrphanedInProgressTickets` removes stale worktree directories with `removeDir(worktreePath)` but does not call `git worktree remove --force` first. This leaves stale entries in `.git/worktrees/` that git continues to track.

The correct pattern is already used in `src/scriptorium/ticket_assignment.nim:323-325` (`cleanupStaleTicketWorktrees`), which calls `git worktree remove --force` first and then `removeDir()` as a fallback.

Recovery Step 1 (`cleanOrphanedWorktrees`) runs before Step 5 but cannot catch the worktrees that Step 5 later removes, so these stale entries persist until the next recovery or cleanup cycle.

## Fix

1. In `reopenOrphanedInProgressTickets` (`src/scriptorium/recovery.nim`), replace the bare `removeDir(worktreePath)` at line 275 with `gitCheck(repoPath, "worktree", "remove", "--force", worktreePath)` followed by `removeDir()` as a fallback (matching the pattern in `ticket_assignment.nim:323-325`). Note: `gitCheck` and the necessary git helper are already imported from `git_ops`.
2. Add a unit test in `tests/test_recovery.nim` that verifies reopening an orphaned ticket also properly removes the git worktree tracking entry (not just the directory).

## Files to modify

- `src/scriptorium/recovery.nim` — `reopenOrphanedInProgressTickets` worktree cleanup
- `tests/test_recovery.nim` — new test case

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0102-use-git-worktree-remove-in-recovery-orphan-reopening

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Single-file fix replacing removeDir with gitCheck+removeDir fallback pattern already established in the codebase, plus one new unit test in an existing test file.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0102/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0102/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes:

- **`src/scriptorium/recovery.nim`**: In `reopenOrphanedInProgressTickets`, replaced `removeDir(worktreePath)` with `discard gitCheck(repoPath, "worktree", "remove", "--force", worktreePath)` followed by `removeDir` as a fallback — matching the pattern in `ticket_assignment.nim:323-328`.
- **`tests/test_recovery.nim`**: Added test "reopening orphaned ticket removes git worktree tracking entry" that creates a real git worktree, verifies it's tracked, triggers recovery, and confirms both the directory and the `.git/worktrees/` tracking entry are removed.
```

### Agent Stdout Tail
```text
, worktreePath)` followed by `removeDir` as a fallback — matching the pattern in `ticket_assignment.nim:323-328`.\n- **`tests/test_recovery.nim`**: Added test \"reopening orphaned ticket removes git worktree tracking entry\" that creates a real git worktree, verifies it's tracked, triggers recovery, and confirms both the directory and the `.git/worktrees/` tracking entry are removed.","stop_reason":"end_turn","session_id":"be4102de-0e76-4b4a-89cd-6e2f69c4f2af","total_cost_usd":0.49314299999999983,"usage":{"input_tokens":6602,"cache_creation_input_tokens":30006,"cache_read_input_tokens":355491,"output_tokens":3794,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":30006},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":6602,"outputTokens":3794,"cacheReadInputTokens":355491,"cacheCreationInputTokens":30006,"webSearchRequests":0,"costUSD":0.49314299999999983,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"728c0851-871f-42d7-bde9-c4c7911a7aa8"}
```
