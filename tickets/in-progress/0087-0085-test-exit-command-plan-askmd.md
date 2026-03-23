# 0085-test-exit-command-plan-ask.md

# Test /exit command works in plan and ask sessions

**Area:** planning-sessions

## Goal

Add unit tests verifying that `/exit` exits the session without invoking the runner, just like `/quit`, in both interactive plan and ask sessions.

## Context

The spec (Section 2) requires both `/quit` and `/exit` to leave the session. The implementation handles both at `src/scriptorium/interactive_sessions.nim` lines 75-76 (plan) and lines 193-194 (ask). However, existing tests only use `/quit` — `/exit` is never tested.

## Tasks

1. In `tests/test_orchestrator_flow.nim`, add a test to the `"interactive planning"` suite:
   - Send `/exit` as the only input
   - Verify the runner is never called
   - Verify the session exits cleanly (no error raised)

2. Add an equivalent test to the `"interactive ask session"` suite for `/exit`.

Follow the existing slash-command test patterns (see the `/show, /help, /quit do not invoke runner` tests).

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0087-0085-test-exit-command-plan-askmd

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 10
- reasoning: Single-file test addition following existing patterns, just duplicating /quit tests with /exit in two test suites.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0087/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0087/attempt-01.last_message.txt\n
### Agent Last Message
```text
The background task already completed successfully — I already read its output and submitted the PR. All done!
```

### Agent Stdout Tail
```text
utput_tokens":1},"context_management":null},"parent_tool_use_id":null,"session_id":"6833bb42-2a95-458a-bd12-10107b4c7edf","uuid":"24179417-7ff4-4e95-bc75-837a171904f7"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":3589,"duration_api_ms":56638,"num_turns":1,"result":"The background task already completed successfully — I already read its output and submitted the PR. All done!","stop_reason":"end_turn","session_id":"6833bb42-2a95-458a-bd12-10107b4c7edf","total_cost_usd":0.4271314999999999,"usage":{"input_tokens":3,"cache_creation_input_tokens":357,"cache_read_input_tokens":36373,"output_tokens":23,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":357},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":18,"outputTokens":1999,"cacheReadInputTokens":295008,"cacheCreationInputTokens":36730,"webSearchRequests":0,"costUSD":0.4271314999999999,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"70cf4ba8-7b88-4bfe-8a24-2cc6f76bbae0"}
```
