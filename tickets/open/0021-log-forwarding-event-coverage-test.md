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

## Merge Queue Failure
- Summary: Add dedicated test verifying onEvent callback wiring in executeAssignedTicket fires all five AgentStreamEventKind values without error\n- Failed gate: git merge --ff-only master\n
### Merge Output
```text
Already up to date.
```

### Quality Check Output
```text
error: Your local changes to the following files would be overwritten by merge:
	tests/test_scriptorium.nim
Please commit your changes or stash them before you merge.
Aborting
Updating 8139084..07be64e
```

## Agent Run
- Model: claude-sonnet-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0021-log-forwarding-event-coverage-test/.scriptorium/logs/0021/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0021-log-forwarding-event-coverage-test/.scriptorium/logs/0021/attempt-01.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` MCP tool returned "Merge request enqueued." successfully.

The work is complete:
- The test `executeAssignedTicket wires onEvent callback that accepts all event kinds` was already committed in `07be64e` by the previous agent run
- It fires all five `AgentStreamEventKind` values (`agentEventTool`, `agentEventStatus`, `agentEventHeartbeat`, `agentEventReasoning`, `agentEventMessage`) through the captured callback
- `make test` passes with `[OK] executeAssignedTicket wires onEvent callback that accepts all event kinds`
- The merge request has been enqueued via the `submit_pr` MCP tool
```

### Agent Stdout Tail
```text
mitted in `07be64e` by the previous agent run\n- It fires all five `AgentStreamEventKind` values (`agentEventTool`, `agentEventStatus`, `agentEventHeartbeat`, `agentEventReasoning`, `agentEventMessage`) through the captured callback\n- `make test` passes with `[OK] executeAssignedTicket wires onEvent callback that accepts all event kinds`\n- The merge request has been enqueued via the `submit_pr` MCP tool","stop_reason":"end_turn","session_id":"2549ba2f-6467-4d65-a90c-33d6c85da1b4","total_cost_usd":0.7793835000000001,"usage":{"input_tokens":36,"cache_creation_input_tokens":23462,"cache_read_input_tokens":949432,"output_tokens":6314,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":23462,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-sonnet-4-6":{"inputTokens":36,"outputTokens":6314,"cacheReadInputTokens":949432,"cacheCreationInputTokens":23462,"webSearchRequests":0,"costUSD":0.7793835000000001,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"081a1200-1313-4990-9a1c-c8739725ccf8"}
```

## Merge Queue Failure
- Summary: Add dedicated test verifying onEvent callback wiring in executeAssignedTicket fires all five AgentStreamEventKind values without error\n- Failed gate: git merge --ff-only master\n
### Merge Output
```text
Already up to date.
```

### Quality Check Output
```text
error: Your local changes to the following files would be overwritten by merge:
	tests/test_scriptorium.nim
Please commit your changes or stash them before you merge.
Aborting
Updating 8139084..07be64e
```

## Agent Run
- Model: claude-sonnet-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 2\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0021-log-forwarding-event-coverage-test/.scriptorium/logs/0021/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0021-log-forwarding-event-coverage-test/.scriptorium/logs/0021/attempt-02.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` MCP tool was called successfully. The response is "Merge request enqueued."

The work for this ticket was already complete from the previous attempt:
- The test `executeAssignedTicket wires onEvent callback that accepts all event kinds` was committed at `07be64e`
- It captures the `onEvent` callback from `AgentRunRequest`, fires all five `AgentStreamEventKind` values through it, and verifies no error is raised
- `make test` passes with `[OK] executeAssignedTicket wires onEvent callback that accepts all event kinds`
- The merge request has now been enqueued
```

### Agent Stdout Tail
```text
empt:\n- The test `executeAssignedTicket wires onEvent callback that accepts all event kinds` was committed at `07be64e`\n- It captures the `onEvent` callback from `AgentRunRequest`, fires all five `AgentStreamEventKind` values through it, and verifies no error is raised\n- `make test` passes with `[OK] executeAssignedTicket wires onEvent callback that accepts all event kinds`\n- The merge request has now been enqueued","stop_reason":"end_turn","session_id":"3ff3da33-de14-447e-a3d9-1632d233da45","total_cost_usd":1.08238225,"usage":{"input_tokens":54,"cache_creation_input_tokens":28801,"cache_read_input_tokens":1430312,"output_tokens":7478,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":28801,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-sonnet-4-6":{"inputTokens":54,"outputTokens":7478,"cacheReadInputTokens":1430312,"cacheCreationInputTokens":28801,"webSearchRequests":0,"costUSD":1.08238225,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"2338df8f-0f9d-48c1-ad1c-b0f012c0b062"}
```

## Merge Queue Failure
- Summary: Add dedicated test verifying onEvent callback wiring in executeAssignedTicket fires all five AgentStreamEventKind values without error\n- Failed gate: git merge --ff-only master\n
### Merge Output
```text
Already up to date.
```

### Quality Check Output
```text
error: Your local changes to the following files would be overwritten by merge:
	tests/test_scriptorium.nim
Please commit your changes or stash them before you merge.
Aborting
Updating 8139084..07be64e
```

## Agent Run
- Model: claude-sonnet-4-6\n- Backend: claude-code\n- Exit Code: 137\n- Attempt: 2\n- Attempt Count: 2\n- Timeout: hard\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0021-log-forwarding-event-coverage-test/.scriptorium/logs/0021/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0021-log-forwarding-event-coverage-test/.scriptorium/logs/0021/attempt-02.last_message.txt\n
### Agent Last Message
```text
The test already exists in the codebase. Let me run the tests to confirm they pass, then submit.
```

### Agent Stdout Tail
```text
user","content":[{"tool_use_id":"toolu_01F3Adp2i1AHdFJX7KZH5LLE","type":"tool_result","content":"grep: warning: stray \\ before d","is_error":false}]},"parent_tool_use_id":null,"session_id":"abcef71c-d655-4fd9-a64e-81013b084873","uuid":"3d2daf51-6c7b-47a2-bb3e-3acdec9bd429","tool_use_result":{"stdout":"grep: warning: stray \\ before d","stderr":"","interrupted":false,"isImage":false,"noOutputExpected":false}}
{"type":"assistant","message":{"model":"claude-sonnet-4-6","id":"msg_01PZPQWPBNKcZhYBSVzZyyjL","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_01EvBFXc8YGTrr8oAcgTJUoP","name":"Bash","input":{"command":"make test 2>&1 | tail -5","description":"Check test output tail","timeout":300000},"caller":{"type":"direct"}}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"cache_creation_input_tokens":131,"cache_read_input_tokens":21072,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":131},"output_tokens":24,"service_tier":"standard","inference_geo":"not_available"},"context_management":null},"parent_tool_use_id":null,"session_id":"abcef71c-d655-4fd9-a64e-81013b084873","uuid":"f01a2758-969e-4f18-afce-b17ed4dca98a"}
```

## Agent Run
- Model: claude-sonnet-4-6\n- Backend: claude-code\n- Exit Code: 137\n- Attempt: 2\n- Attempt Count: 2\n- Timeout: hard\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0021-log-forwarding-event-coverage-test/.scriptorium/logs/0021/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0021-log-forwarding-event-coverage-test/.scriptorium/logs/0021/attempt-02.last_message.txt\n
### Agent Last Message
```text
Tests pass including `[OK] executeAssignedTicket wires onEvent callback that accepts all event kinds`. The test is already in master and the branch is clean. Let me submit.
```

### Agent Stdout Tail
```text
d":"9e13f008-a919-41eb-9a31-3c057626387d"}
{"type":"assistant","message":{"model":"claude-sonnet-4-6","id":"msg_011mN5eorJ8sP5omYn6mxFZ8","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_0111etpy139tDhg9cpYN2mAZ","name":"ToolSearch","input":{"query":"select:mcp__scriptorium__submit_pr","max_results":3},"caller":{"type":"direct"}}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"cache_creation_input_tokens":230,"cache_read_input_tokens":26726,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":230},"output_tokens":8,"service_tier":"standard","inference_geo":"not_available"},"context_management":null},"parent_tool_use_id":null,"session_id":"97444cfd-c024-4c91-9676-77b87b02d8f6","uuid":"6f76e8ec-9a78-4caf-bb15-982a69b74bed"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_0111etpy139tDhg9cpYN2mAZ","content":"No matching deferred tools found"}]},"parent_tool_use_id":null,"session_id":"97444cfd-c024-4c91-9676-77b87b02d8f6","uuid":"b9be7deb-c3a5-4175-a5df-a24d654bb139","tool_use_result":{"matches":[],"query":"select:mcp__scriptorium__submit_pr","total_deferred_tools":13}}
```

## Agent Run
- Model: claude-sonnet-4-6\n- Backend: claude-code\n- Exit Code: 137\n- Attempt: 2\n- Attempt Count: 2\n- Timeout: hard\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0021-log-forwarding-event-coverage-test/.scriptorium/logs/0021/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0021-log-forwarding-event-coverage-test/.scriptorium/logs/0021/attempt-02.last_message.txt\n
### Agent Last Message
```text
The test already exists in master (added in commit `4110084`). The ticket-0021 branch at `c40834e` already has the test, and master at `405137d` also has it. The previous merge failures were caused by uncommitted changes in the broken old worktree.

The new clean worktree is at `c40834e` with no uncommitted changes. Let me run tests to confirm everything passes, then submit:
```

### Agent Stdout Tail
```text
:{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":142},"output_tokens":8,"service_tier":"standard","inference_geo":"not_available"},"context_management":null},"parent_tool_use_id":null,"session_id":"21d1cb5e-e123-4591-8099-6c3e3e99d680","uuid":"160d6e8b-c44d-4a97-a698-e98c43becf55"}
{"type":"assistant","message":{"model":"claude-sonnet-4-6","id":"msg_01KLPm7etwaKWuPvf8rdWT8T","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_01T2ZBrUwH5W6QcnLzySFyVT","name":"Bash","input":{"command":"cd /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0021-log-forwarding-event-coverage-test-new && make test 2>&1 | tail -20","description":"Run tests in the new worktree","timeout":300000},"caller":{"type":"direct"}}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"cache_creation_input_tokens":142,"cache_read_input_tokens":33640,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":142},"output_tokens":8,"service_tier":"standard","inference_geo":"not_available"},"context_management":null},"parent_tool_use_id":null,"session_id":"21d1cb5e-e123-4591-8099-6c3e3e99d680","uuid":"9947a4dc-1749-4050-bba9-cef2b72723b3"}
```
