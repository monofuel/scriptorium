# Change Default maxAgents From 1 To 4

**Area:** config-testing

## Problem

Per V13 §27, `concurrency.maxAgents` should default to 4 (changed from 1). The current implementation in `src/scriptorium/config.nim` defaults to 1.

## Requirements

1. In `src/scriptorium/config.nim`, change the `defaultConfig()` proc so `concurrency.maxAgents` defaults to 4 instead of 1.
2. Update unit tests in `tests/test_scriptorium.nim` that assert the default value of `maxAgents` — change expected value from 1 to 4.
3. Verify `make test` passes after the change.

## Files To Modify

- `src/scriptorium/config.nim`: Change default `maxAgents: 1` to `maxAgents: 4`.
- `tests/test_scriptorium.nim`: Update test assertions for default `maxAgents` value.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0064-default-maxagents-to-four

## Prediction
- predicted_difficulty: trivial
- predicted_duration_minutes: 5
- reasoning: Two-line change across two files (default value 1→4 and corresponding test assertion), no logic complexity or integration risk.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 2\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0064-default-maxagents-to-four/.scriptorium/logs/0064/attempt-02.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0064-default-maxagents-to-four/.scriptorium/logs/0064/attempt-02.last_message.txt\n
### Agent Last Message
```text
Tests completed successfully (exit code 0). The work is already committed and the PR has been submitted.
```

### Agent Stdout Tail
```text
l_1h_input_tokens":0},"output_tokens":1},"context_management":null},"parent_tool_use_id":null,"session_id":"ad9f13b3-8980-496f-bbce-9cc516b9d582","uuid":"ada3eb14-9107-4907-886b-2bd9b8cb9b0b"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":2871,"duration_api_ms":36009,"num_turns":1,"result":"Tests completed successfully (exit code 0). The work is already committed and the PR has been submitted.","stop_reason":"end_turn","session_id":"ad9f13b3-8980-496f-bbce-9cc516b9d582","total_cost_usd":0.22265425,"usage":{"input_tokens":3,"cache_creation_input_tokens":306,"cache_read_input_tokens":22099,"output_tokens":24,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":306},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":16,"outputTokens":1023,"cacheReadInputTokens":113936,"cacheCreationInputTokens":22405,"webSearchRequests":0,"costUSD":0.22265425,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"07452235-d8a7-4507-bc60-facaa24fe933"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 12s
