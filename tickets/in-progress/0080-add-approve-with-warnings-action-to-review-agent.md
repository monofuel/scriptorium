<!-- ticket: 0074-approve-with-warnings-action.md -->
# Add `approve_with_warnings` action to review agent

**Area:** review-agent
**Difficulty:** medium

## Problem

The `submit_review` MCP tool in `src/scriptorium/mcp_server.nim` only supports two actions: `approve` and `request_changes`. The spec (Section 9) and area definition require a third action: `approve_with_warnings`, which accepts the changes but logs warnings for minor style issues.

## Requirements

1. **MCP tool update** (`src/scriptorium/mcp_server.nim`):
   - Add `"approve_with_warnings"` to the `enum` array in the `submit_review` tool's `inputSchema`.
   - Update the validation in `submitReviewHandler` to accept `approve_with_warnings` as a valid action.
   - When `action` is `approve_with_warnings`, `feedback` should be accepted (warnings text) but not required.

2. **Merge queue handling** (`src/scriptorium/merge_queue.nim`):
   - In `runReviewAgent`, handle `approve_with_warnings` as a successful review (merge proceeds).
   - Log at INFO level: `ticket <id>: review approved with warnings`.
   - Append a structured review note to the ticket markdown that includes the warnings text from `feedback`. Use a format like:

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0080-add-approve-with-warnings-action-to-review-agent

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Two-file change adding a new enum variant and a simple branch in the review handler — the logic mirrors existing approve/request_changes paths with no complex integration risk.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0080-add-approve-with-warnings-action-to-review-agent/.scriptorium/logs/0080/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0080-add-approve-with-warnings-action-to-review-agent/.scriptorium/logs/0080/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes in two files:

- **`src/scriptorium/mcp_server.nim`**: Added `"approve_with_warnings"` to the enum array and updated validation to accept it as a valid action (feedback accepted but not required).
- **`src/scriptorium/merge_queue.nim`**: Added `approve_with_warnings` branch in `runReviewAgent` — logs at INFO level (`ticket <id>: review approved with warnings`), generates a structured review note with `**Review:** approved with warnings` and optional `**Warnings:**` section from feedback. The action falls through to merge (same as approve) since `processMergeQueue` only blocks on `request_changes`.
```

### Agent Stdout Tail
```text
m/merge_queue.nim`**: Added `approve_with_warnings` branch in `runReviewAgent` — logs at INFO level (`ticket <id>: review approved with warnings`), generates a structured review note with `**Review:** approved with warnings` and optional `**Warnings:**` section from feedback. The action falls through to merge (same as approve) since `processMergeQueue` only blocks on `request_changes`.","stop_reason":"end_turn","session_id":"01c85660-504e-4c03-9173-37fea877e27c","total_cost_usd":0.7688397499999999,"usage":{"input_tokens":9613,"cache_creation_input_tokens":49269,"cache_read_input_tokens":633387,"output_tokens":3846,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":49269},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":9613,"outputTokens":3846,"cacheReadInputTokens":633387,"cacheCreationInputTokens":49269,"webSearchRequests":0,"costUSD":0.7688397499999999,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"67be272b-f160-4d2d-a31b-30bbf6330066"}
```
