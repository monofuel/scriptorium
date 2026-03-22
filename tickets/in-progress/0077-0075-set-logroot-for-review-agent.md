# 0075 — Set logRoot for review agent

**Area:** log-persistence

## Problem

The review agent's `AgentRunRequest` in `src/scriptorium/merge_queue.nim` (around line 213) does not set `logRoot`, so JSONL logs are written inside the ticket worktree. These logs are lost when the worktree is cleaned up after merge.

## Task

In `src/scriptorium/merge_queue.nim`, in the `runReviewAgent` function, add the `logRoot` field to the `AgentRunRequest`:

```nim
logRoot: repoPath / ManagedStateDirName / PlanLogDirName / "review",

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0077-0075-set-logroot-for-review-agent

## Prediction
- predicted_difficulty: trivial
- predicted_duration_minutes: 5
- reasoning: Single-line addition of a logRoot field to an existing AgentRunRequest struct in one file, with the exact code provided in the ticket.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0077-0075-set-logroot-for-review-agent/.scriptorium/logs/0077/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0077-0075-set-logroot-for-review-agent/.scriptorium/logs/0077/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Added `logRoot: repoPath / ManagedStateDirName / PlanLogDirName / "review"` to the review agent's `AgentRunRequest` in `merge_queue.nim` (and added the `architect_agent` import for `PlanLogDirName`). Merge request submitted.
```

### Agent Stdout Tail
```text
79304d9d-fcfa-4875-adb0-8f40f065ffdd"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":81542,"duration_api_ms":79996,"num_turns":20,"result":"Done. Added `logRoot: repoPath / ManagedStateDirName / PlanLogDirName / \"review\"` to the review agent's `AgentRunRequest` in `merge_queue.nim` (and added the `architect_agent` import for `PlanLogDirName`). Merge request submitted.","stop_reason":"end_turn","session_id":"09354b61-aeaa-4b44-b77c-e14f6746b54f","total_cost_usd":0.3496524999999999,"usage":{"input_tokens":26,"cache_creation_input_tokens":20572,"cache_read_input_tokens":300945,"output_tokens":2819,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":20572},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":26,"outputTokens":2819,"cacheReadInputTokens":300945,"cacheCreationInputTokens":20572,"webSearchRequests":0,"costUSD":0.3496524999999999,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"6111ed6b-18c3-4449-abfb-8aac880513fc"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 17s
