# Forward status events from coding agent to orchestrator logs

The coding agent `onEvent` callback in `executeAssignedTicket` currently filters to tool events only:

```nim
onEvent: proc(event: AgentStreamEvent) =
  if event.kind == agentEventTool:
    logDebug(fmt"coding[{ticketId}]: {event.text}"),
```

The spec (Section 10) requires status change events to also be forwarded so operators can see agent status transitions like "agent: thinking" and "agent: executing tool" in real time.

## Task

Expand the coding agent `onEvent` callback in `executeAssignedTicket` to forward `agentEventStatus` events in addition to `agentEventTool` events. Status events should be logged at DEBUG level with the same ticket ID prefix format.

The callback should forward:
- `agentEventTool` — already forwarded, no change needed.
- `agentEventStatus` — add forwarding with format `coding[{ticketId}]: status {event.text}`.

Do not forward heartbeat, reasoning, or message events — these are high-volume and not required by the spec.

## Files

- `src/scriptorium/orchestrator.nim:1857` — coding agent `onEvent` callback in `executeAssignedTicket`
- `src/scriptorium/agent_runner.nim:6` — `AgentStreamEventKind` enum (reference, do not modify)

## Acceptance criteria

- `agentEventStatus` events are logged at DEBUG level with ticket ID prefix.
- `agentEventTool` events continue to be logged as before.
- Heartbeat, reasoning, and message events are not forwarded.
- `make test` passes.

**Area:** log-forwarding

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0019-coding-agent-status-event-forwarding

## Agent Run
- Model: claude-sonnet-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0019-coding-agent-status-event-forwarding/.scriptorium/logs/0019/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0019-coding-agent-status-event-forwarding/.scriptorium/logs/0019/attempt-01.last_message.txt\n
### Agent Last Message
```text
The change is minimal and complete. Here's a summary of what was done:

**Change:** `src/scriptorium/orchestrator.nim:1859-1861`

Added an `elif` branch to the coding agent's `onEvent` callback to forward `agentEventStatus` events alongside the existing `agentEventTool` forwarding:

```nim
onEvent: proc(event: AgentStreamEvent) =
  if event.kind == agentEventTool:
    logDebug(fmt"coding[{ticketId}]: {event.text}")
  elif event.kind == agentEventStatus:
    logDebug(fmt"coding[{ticketId}]: status {event.text}"),
```

The `submit_pr` MCP tool returned "Merge request enqueued."
```

### Agent Stdout Tail
```text
ack to forward `agentEventStatus` events alongside the existing `agentEventTool` forwarding:\n\n```nim\nonEvent: proc(event: AgentStreamEvent) =\n  if event.kind == agentEventTool:\n    logDebug(fmt\"coding[{ticketId}]: {event.text}\")\n  elif event.kind == agentEventStatus:\n    logDebug(fmt\"coding[{ticketId}]: status {event.text}\"),\n```\n\nThe `submit_pr` MCP tool returned \"Merge request enqueued.\"","stop_reason":"end_turn","session_id":"77cb543d-81a7-433a-888b-868d8c03fbea","total_cost_usd":0.6368109999999999,"usage":{"input_tokens":39,"cache_creation_input_tokens":20458,"cache_read_input_tokens":784357,"output_tokens":4663,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":20458,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-sonnet-4-6":{"inputTokens":39,"outputTokens":4663,"cacheReadInputTokens":784357,"cacheCreationInputTokens":20458,"webSearchRequests":0,"costUSD":0.6368109999999999,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"529cc6ce-916c-4f69-b71a-670d0508fd6a"}
```
