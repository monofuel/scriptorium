# 0090 Use dynamic default branch name in health cache log messages

**Area:** health-cache
**Priority:** medium

## Summary

The `isMasterHealthy` proc in `src/scriptorium/orchestrator.nim` hardcodes "master" in its log messages (e.g., `master health: cached healthy for ...`, `master is unhealthy — skipping tick`). The spec requires these messages to use the actual resolved default branch name (which may be `main`, `develop`, etc.).

## Acceptance criteria

- Call `resolveDefaultBranch(repoPath)` (from `git_ops`) once at the start of `isMasterHealthy` and use the result in all log messages.
- The log lines in `isMasterHealthy` should read e.g. `main health: cached healthy for <hash>` when the default branch is `main`.
- Also update the log lines at orchestrator.nim lines 232 and 235 that say "master is unhealthy" / "master is healthy again" to use the dynamic branch name.
- Update the debug log at line 226 (`checking master health`) similarly.
- Do not rename the proc or the `MasterHealthState` type — only change the string literals in log calls.

## Files to modify

- `src/scriptorium/orchestrator.nim`

## Notes

- `resolveDefaultBranch` is already imported via `git_ops`. Use `&` format strings per project convention.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0094-0090-use-dynamic-default-branch-name-in-health-cache-log-messages

## Prediction
- predicted_difficulty: trivial
- predicted_duration_minutes: 5
- reasoning: Single-file string literal replacements in log messages, calling an already-imported function, with no logic or architectural changes.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0094/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0094/attempt-01.last_message.txt\n
### Agent Last Message
```text
Changes submitted. The single file `src/scriptorium/orchestrator.nim` was modified to:

1. Call `resolveDefaultBranch(repoPath)` at the start of `isMasterHealthy` and use the result (`branchName`) in the cached healthy/unhealthy log lines.
2. Call `resolveDefaultBranch(repoPath)` in the orchestrator loop and use `defaultBranch` in the "checking health", "health check took", "is unhealthy", and "is healthy again" log lines.
```

### Agent Stdout Tail
```text
 file `src/scriptorium/orchestrator.nim` was modified to:\n\n1. Call `resolveDefaultBranch(repoPath)` at the start of `isMasterHealthy` and use the result (`branchName`) in the cached healthy/unhealthy log lines.\n2. Call `resolveDefaultBranch(repoPath)` in the orchestrator loop and use `defaultBranch` in the \"checking health\", \"health check took\", \"is unhealthy\", and \"is healthy again\" log lines.","stop_reason":"end_turn","session_id":"3388f6fa-1a07-4859-8864-bff5d0ac2e2c","total_cost_usd":0.40964524999999996,"usage":{"input_tokens":24,"cache_creation_input_tokens":16263,"cache_read_input_tokens":433913,"output_tokens":3637,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":16263,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":24,"outputTokens":3637,"cacheReadInputTokens":433913,"cacheCreationInputTokens":16263,"webSearchRequests":0,"costUSD":0.40964524999999996,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"16a335fa-ce3e-42f0-b921-5937b8a8bc48"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 42s

**Review Reasoning:** Let me review the changes carefully.
The changes are straightforward and correct. Let me verify one thing about the `resolveDefaultBranch` function.
Good — `resolveDefaultBranch` is available from `git_ops` as expected. Now let me submit the review.


The changes are clean and correct. All ticket requirements are met:

1. `resolveDefaultBranch(repoPath)` is called at the start of `isMasterHealthy` and used in the cached healthy/unhealthy log lines.
2. The orchestrator loop log lines for "checking health", "health check took", "is unhealthy", and "is healthy again" all use the dynamic branch name.
3. No proc or type renames — only string literals changed.
4. `&` format strings used per convention, with values assigned to variables before interpolation.

Minor observation: `resolveDefaultBranch` is called twice per tick (once in the orchestrator loop, once inside `isMasterHealthy`), but the ticket explicitly asks for it at the start of `isMasterHealthy` and the outer log lines also need it. Avoiding the duplication would require changing the proc signature, which the ticket forbids. This is fine.

The inconsistent variable naming (`branchName` inside `isMasterHealthy` vs `defaultBranch` in the loop) is trivial and both are valid camelCase.
Review approved. The implementation is correct, minimal, and follows all project conventions.
