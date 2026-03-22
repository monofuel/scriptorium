# 0076 — Set logRoot for prediction agent

**Area:** log-persistence

## Problem

The prediction agent's `AgentRunRequest` in `src/scriptorium/coding_agent.nim` (around line 78) does not set `logRoot`. Currently it uses ticketId `"{ticketId}-prediction"` which causes logs to land at `<repoPath>/.scriptorium/logs/{ticketId}-prediction/` (the default fallback). The area spec requires `prediction/<ticketId>/` structure instead.

## Task

In `src/scriptorium/coding_agent.nim`, in `predictTicketDifficulty` (around line 78):

1. Add the `logRoot` field to the `AgentRunRequest`:
   ```nim
   logRoot: repoPath / ManagedStateDirName / PlanLogDirName / "prediction",

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0078-0076-set-logroot-for-prediction-agent

## Prediction
- predicted_difficulty: trivial
- predicted_duration_minutes: 5
- reasoning: Single-line addition of a logRoot field to an existing AgentRunRequest struct in one file, no logic changes or tests needed.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0078-0076-set-logroot-for-prediction-agent/.scriptorium/logs/0078/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0078-0076-set-logroot-for-prediction-agent/.scriptorium/logs/0078/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Added `logRoot: repoPath / ManagedStateDirName / PlanLogDirName / "prediction"` to the prediction agent's `AgentRunRequest` in `src/scriptorium/coding_agent.nim:84`, so logs will persist at the correct `prediction/<ticketId>/` structure. PR submitted.
```

### Agent Stdout Tail
```text
82-6cd3-4281-98cb-f8261b1a83be"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":28967,"duration_api_ms":28785,"num_turns":7,"result":"\n\nDone. Added `logRoot: repoPath / ManagedStateDirName / PlanLogDirName / \"prediction\"` to the prediction agent's `AgentRunRequest` in `src/scriptorium/coding_agent.nim:84`, so logs will persist at the correct `prediction/<ticketId>/` structure. PR submitted.","stop_reason":"end_turn","session_id":"397d2907-428e-407f-88e3-e5b6d016217e","total_cost_usd":0.128511,"usage":{"input_tokens":12,"cache_creation_input_tokens":11696,"cache_read_input_tokens":60802,"output_tokens":998,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":11696},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":12,"outputTokens":998,"cacheReadInputTokens":60802,"cacheCreationInputTokens":11696,"webSearchRequests":0,"costUSD":0.128511,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"b4619ae9-7127-49b8-8790-4a82504a5495"}
```
