# Test coding agent log forwarding event coverage

The spec (Section 10) requires that during coding agent execution, tool calls, file activity, and status changes are forwarded to orchestrator logs with ticket ID prefix. There is no dedicated test verifying that the `onEvent` callback in `executeAssignedTicket` forwards the correct event types with the expected log format.

## Current state

The existing `executeAssignedTicket` test at `tests/test_scriptorium.nim:972` uses a fake runner but does not verify:
- Which event kinds the `onEvent` callback accepts (tool, status).
- Which event kinds the callback ignores (heartbeat, reasoning, message).
- That log output includes the ticket ID prefix format `coding[{ticketId}]:`.

## Task

Add a dedicated test in `tests/test_scriptorium.nim` that verifies the `onEvent` callback wired by `executeAssignedTicket` forwards the correct event types. The test should:

1. Capture the `onEvent` callback from the `AgentRunRequest` passed to the fake runner.
2. Fire synthetic events of each kind (`agentEventTool`, `agentEventStatus`, `agentEventHeartbeat`, `agentEventReasoning`, `agentEventMessage`) through the callback.
3. Verify that tool and status events are accepted without error.
4. Verify that the callback is not nil (already checked in existing tests, but confirm in context of this test).

Since `logDebug` writes to stdout/file and is hard to capture in unit tests, the test should focus on verifying:
- The callback is wired (not nil).
- The callback does not raise when called with expected event types.
- The callback can be called with all five event kinds without crashing.

## Files

- `tests/test_scriptorium.nim` — add test near existing `executeAssignedTicket` tests
- `src/scriptorium/orchestrator.nim:1857` — `onEvent` callback (reference)
- `src/scriptorium/agent_runner.nim:6` — `AgentStreamEventKind` enum (reference)

## Acceptance criteria

- New test verifies `onEvent` is wired and callable with all event kinds.
- Test fires tool and status events through the callback without error.
- `make test` passes.

**Area:** log-forwarding

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0021-log-forwarding-event-coverage-test

## Agent Run
- Model: claude-sonnet-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 2\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0021-log-forwarding-event-coverage-test/.scriptorium/logs/0021/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0021-log-forwarding-event-coverage-test/.scriptorium/logs/0021/attempt-02.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` MCP tool was called successfully. The work is complete:

- The previous attempt already added a dedicated test in `tests/test_scriptorium.nim` that:
  1. Captures the `onEvent` callback from the `AgentRunRequest` passed to the fake runner
  2. Fires synthetic events of all five `AgentStreamEventKind` values (`agentEventTool`, `agentEventStatus`, `agentEventHeartbeat`, `agentEventReasoning`, `agentEventMessage`) through the callback
  3. Verifies the callback is non-nil
  4. Verifies no event kind raises an error
- `make test` passes with `[OK] executeAssignedTicket wires onEvent callback that accepts all event kinds`
- The merge request has been enqueued via the `submit_pr` MCP tool
```

### Agent Stdout Tail
```text
ll five `AgentStreamEventKind` values (`agentEventTool`, `agentEventStatus`, `agentEventHeartbeat`, `agentEventReasoning`, `agentEventMessage`) through the callback\n  3. Verifies the callback is non-nil\n  4. Verifies no event kind raises an error\n- `make test` passes with `[OK] executeAssignedTicket wires onEvent callback that accepts all event kinds`\n- The merge request has been enqueued via the `submit_pr` MCP tool","stop_reason":"end_turn","session_id":"5d642727-32b7-40ec-a36c-9b5bd1225e10","total_cost_usd":0.43854425,"usage":{"input_tokens":26,"cache_creation_input_tokens":17453,"cache_read_input_tokens":507616,"output_tokens":3021,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":17453,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-sonnet-4-6":{"inputTokens":26,"outputTokens":3021,"cacheReadInputTokens":507616,"cacheCreationInputTokens":17453,"webSearchRequests":0,"costUSD":0.43854425,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"24af13dc-1990-41c6-8952-52a43fbc6ea8"}
```
