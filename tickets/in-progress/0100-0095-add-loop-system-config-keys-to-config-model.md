<!-- ticket: 0095-add-loop-config-keys.md -->
# 0095 — Add loop system config keys to Config model

**Area:** config-testing

## Description

The spec (Section 22: Loop System) defines four config keys under `loop.*` that are
not yet present in the `Config` type or `loadConfig` proc. Add them so the
orchestrator (and future loop implementation) can read them from `scriptorium.json`.

### Required changes

**`src/scriptorium/config.nim`**

1. Add a new `LoopConfig` object type:

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0100-0095-add-loop-system-config-keys-to-config-model

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 11
- reasoning: Adding a new LoopConfig object type and four fields to the Config model with loadConfig parsing is a single-file change with straightforward struct/deserialization work plus unit tests.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0100/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0100/attempt-01.last_message.txt\n
### Agent Last Message
```text
The background `make test` run also completed successfully. The PR has been submitted — all done.
```

### Agent Stdout Tail
```text
okens":0},"output_tokens":1},"context_management":null},"parent_tool_use_id":null,"session_id":"2a238dee-6c5a-4a56-93c6-c5eaf499237d","uuid":"a38736bc-21b7-4362-8fbe-ff8e24eb605a"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":3537,"duration_api_ms":114217,"num_turns":1,"result":"The background `make test` run also completed successfully. The PR has been submitted — all done.","stop_reason":"end_turn","session_id":"2a238dee-6c5a-4a56-93c6-c5eaf499237d","total_cost_usd":0.6021952500000002,"usage":{"input_tokens":3,"cache_creation_input_tokens":399,"cache_read_input_tokens":35504,"output_tokens":23,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":399},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":58,"outputTokens":4498,"cacheReadInputTokens":530123,"cacheCreationInputTokens":35903,"webSearchRequests":0,"costUSD":0.6021952500000002,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"2050f276-bfd6-4aab-8780-279f32595f01"}
```
