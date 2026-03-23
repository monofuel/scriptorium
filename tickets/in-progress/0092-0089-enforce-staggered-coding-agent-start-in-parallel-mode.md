# 0089 Enforce staggered coding agent start in parallel mode

**Area:** orchestrator

## Problem

The area spec requires "at most 1 new coding agent per tick — staggered start rule" in parallel mode. However, `orchestrator.nim:291-296` calls `assignOpenTickets(repoPath, slotsAvailable)` where `slotsAvailable` can be greater than 1, then starts all returned assignments in a single tick. This violates the staggered start rule and can overwhelm the system with simultaneous agent startups.

## Task

In `src/scriptorium/orchestrator.nim`, limit the number of new coding agents started per tick to 1 when `maxAgents > 1`. The simplest fix is to cap the argument to `assignOpenTickets` at 1:

```nim
let assignments = assignOpenTickets(repoPath, 1)

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0092-0089-enforce-staggered-coding-agent-start-in-parallel-mode

## Prediction
- predicted_difficulty: trivial
- predicted_duration_minutes: 5
- reasoning: Single-line change capping assignOpenTickets argument to 1, isolated to one location in orchestrator.nim with no cross-module impact.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0092/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0092/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changed `assignOpenTickets(repoPath, slotsAvailable)` to `assignOpenTickets(repoPath, 1)` at `orchestrator.nim:292`, enforcing the "at most 1 new coding agent per tick" staggered start rule.
```

### Agent Stdout Tail
```text
d":"3c98700e-dfee-498a-be28-329edad33098","uuid":"d4a527c2-64e0-4de9-8c4c-9040d329c6a6"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":50747,"duration_api_ms":49136,"num_turns":11,"result":"Done. Changed `assignOpenTickets(repoPath, slotsAvailable)` to `assignOpenTickets(repoPath, 1)` at `orchestrator.nim:292`, enforcing the \"at most 1 new coding agent per tick\" staggered start rule.","stop_reason":"end_turn","session_id":"3c98700e-dfee-498a-be28-329edad33098","total_cost_usd":0.18687925,"usage":{"input_tokens":14,"cache_creation_input_tokens":13885,"cache_read_input_tokens":118706,"output_tokens":1627,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":13885},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":14,"outputTokens":1627,"cacheReadInputTokens":118706,"cacheCreationInputTokens":13885,"webSearchRequests":0,"costUSD":0.18687925,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"7c3b1eb5-e571-4017-a1a2-1558954ac8b1"}
```
