# 0074 — Set logRoot for coding agent

**Area:** log-persistence

## Problem

The coding agent's `AgentRunRequest` does not set `logRoot`, so JSONL logs are written inside the ticket worktree under `<worktree>/.scriptorium/logs/<ticketId>/`. When the worktree is cleaned up after merge, these logs are lost.

## Task

In `src/scriptorium/coding_agent.nim`, in the `executeAssignedTicket` function (around line 176), add the `logRoot` field to the `AgentRunRequest`:

```nim
logRoot: repoPath / ManagedStateDirName / PlanLogDirName / "coder",

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0076-0074-set-logroot-for-coding-agent

## Prediction
- predicted_difficulty: trivial
- predicted_duration_minutes: 5
- reasoning: Single-line addition of a logRoot field to an existing record literal in one file, with the exact code provided in the ticket.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0076-0074-set-logroot-for-coding-agent/.scriptorium/logs/0076/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0076-0074-set-logroot-for-coding-agent/.scriptorium/logs/0076/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Added `logRoot: repoPath / ManagedStateDirName / PlanLogDirName / "coder"` to the `AgentRunRequest` in `coding_agent.nim` and imported `architect_agent` for the `PlanLogDirName` constant. Build compiles cleanly.
```

### Agent Stdout Tail
```text
620-91dd-3001deaf3378","uuid":"a16a714a-1c4f-4f9e-9571-34016ef2c115"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":74096,"duration_api_ms":71152,"num_turns":15,"result":"Done. Added `logRoot: repoPath / ManagedStateDirName / PlanLogDirName / \"coder\"` to the `AgentRunRequest` in `coding_agent.nim` and imported `architect_agent` for the `PlanLogDirName` constant. Build compiles cleanly.","stop_reason":"end_turn","session_id":"22795ca6-8222-4620-91dd-3001deaf3378","total_cost_usd":0.2416735,"usage":{"input_tokens":18,"cache_creation_input_tokens":14760,"cache_read_input_tokens":169817,"output_tokens":2577,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":14760},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":18,"outputTokens":2577,"cacheReadInputTokens":169817,"cacheCreationInputTokens":14760,"webSearchRequests":0,"costUSD":0.2416735,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"733cdb5d-5183-4249-9882-744a929d52ad"}
```
