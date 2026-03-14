# Worktree Health Check Before Retry

**Area:** agent-execution

Implement worktree health validation before starting any retry attempt (stall, progress timeout, or crash) as specified in V8, §34.

## Requirements

Before each retry in `executeAssignedTicket` (in `coding_agent.nim`), validate the worktree:

1. **Corruption check:** Run `git status --porcelain` in the worktree. If it fails (non-zero exit), the worktree is corrupt.
   - Remove and recreate from ticket branch: `git worktree remove --force <path>` then `git worktree add <path> <branch>`.
   - Log: `ticket <id>: worktree corrupt, recreated from branch`.

2. **Uncommitted changes:** If `git status --porcelain` succeeds but has output, there are uncommitted changes.
   - Stage all and commit with message `scriptorium: save partial agent work (attempt <n>)` on the ticket branch.
   - Log: `ticket <id>: saved uncommitted agent work before retry`.

3. **Clean worktree:** If `git status --porcelain` succeeds with no output, proceed normally.

## Implementation Notes

- Insert the health check in the `while totalAttemptsUsed < maxAttempts` loop in `executeAssignedTicket`, just before the stall continuation prompt is built (around the `if isStall` block).
- Use existing `runCommandCapture` / `gitRun` / `gitCheck` helpers from `git_ops.nim`.
- The retry agent receives the worktree in a known-good state with all prior work committed.

## Acceptance Criteria

- Corrupt worktree is detected, removed, and recreated before retry.
- Uncommitted changes are committed before retry with the specified message format.
- Clean worktrees proceed without extra operations.
- Each case produces the specified log message.
- Unit tests cover all three cases (corrupt, dirty, clean).

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0063-worktree-health-check-before-retry

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Single-file insertion of a three-branch conditional (corrupt/dirty/clean) into an existing retry loop using established git helpers, plus unit tests for each case — moderate logic but well-scoped with clear implementation guidance.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0063-worktree-health-check-before-retry/.scriptorium/logs/0063/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0063-worktree-health-check-before-retry/.scriptorium/logs/0063/attempt-01.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` MCP tool is not available as a deferred tool in this session. All changes are committed. Let me provide a summary:

**Done.** Implemented worktree health check before retry attempts:

**Changes:**
1. **`src/scriptorium/coding_agent.nim`** — Added `validateWorktreeHealth*` proc that checks worktree state before retries:
   - **Corrupt**: If `git status --porcelain` fails, removes and recreates worktree from branch
   - **Dirty**: If there are uncommitted changes, stages all and commits with `scriptorium: save partial agent work (attempt N)`
   - **Clean**: No action needed
   - Called in the `while totalAttemptsUsed < maxAttempts` loop when `totalAttemptsUsed > 0`

2. **`tests/test_worktree_health.nim`** — Unit tests covering all three cases (clean, dirty, corrupt), each verifying correct behavior and log messages.

Note: The `submit_pr` MCP tool is not available in this environment. The commit is ready on branch `scriptorium/ticket-0063`.
```

### Agent Stdout Tail
```text
 (attempt N)`\n   - **Clean**: No action needed\n   - Called in the `while totalAttemptsUsed < maxAttempts` loop when `totalAttemptsUsed > 0`\n\n2. **`tests/test_worktree_health.nim`** — Unit tests covering all three cases (clean, dirty, corrupt), each verifying correct behavior and log messages.\n\nNote: The `submit_pr` MCP tool is not available in this environment. The commit is ready on branch `scriptorium/ticket-0063`.","stop_reason":"end_turn","session_id":"1ef64591-f671-479a-90d2-77e2c12686d6","total_cost_usd":0.935539,"usage":{"input_tokens":30,"cache_creation_input_tokens":39564,"cache_read_input_tokens":1004328,"output_tokens":7438,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":39564,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":30,"outputTokens":7438,"cacheReadInputTokens":1004328,"cacheCreationInputTokens":39564,"webSearchRequests":0,"costUSD":0.935539,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"9713e4a2-b591-4af7-ba0f-da31915aa382"}
```

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0063-worktree-health-check-before-retry/.scriptorium/logs/0063/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0063-worktree-health-check-before-retry/.scriptorium/logs/0063/attempt-02.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` MCP tool returned successfully: **"Merge request enqueued."**

The work for ticket 0063 is complete:
- **Worktree health check** added to `coding_agent.nim` before retry attempts
- Handles all three cases: corrupt worktree (remove & recreate), dirty worktree (commit changes), clean worktree (proceed)
- **Unit tests** covering all three cases in `tests/test_worktree_health.nim`
- All tests passing
```

### Agent Stdout Tail
```text
":"The `submit_pr` MCP tool returned successfully: **\"Merge request enqueued.\"**\n\nThe work for ticket 0063 is complete:\n- **Worktree health check** added to `coding_agent.nim` before retry attempts\n- Handles all three cases: corrupt worktree (remove & recreate), dirty worktree (commit changes), clean worktree (proceed)\n- **Unit tests** covering all three cases in `tests/test_worktree_health.nim`\n- All tests passing","stop_reason":"end_turn","session_id":"d024cef0-8bb1-4e7f-9238-702560aedae9","total_cost_usd":0.61667875,"usage":{"input_tokens":36,"cache_creation_input_tokens":23661,"cache_read_input_tokens":744285,"output_tokens":3859,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":23661,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":36,"outputTokens":3859,"cacheReadInputTokens":744285,"cacheCreationInputTokens":23661,"webSearchRequests":0,"costUSD":0.61667875,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"f541541f-b89d-4b6c-b433-5b0c92557e48"}
```
