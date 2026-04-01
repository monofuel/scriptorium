# 0091 Wire log forwarding into all agent roles

**Area:** log-forwarding
**Priority:** medium
**Depends:** 0090

## Summary

Replace the ad-hoc `onEvent` callback implementations in all four agent roles (coding, manager, architect, review) with calls to the shared `forwardAgentEvent` proc from `log_forwarding.nim`.

## Requirements

### Coding agent (`src/scriptorium/coding_agent.nim`)

Current handler (around line 196):
```nim
onEvent: proc(event: AgentStreamEvent) =
  if event.kind == agentEventTool:
    logDebug(fmt"coding[{ticketId}]: {event.text}")
  elif event.kind == agentEventStatus:
    logDebug(fmt"coding[{ticketId}]: status {event.text}"),
```

Replace with:
```nim
onEvent: proc(event: AgentStreamEvent) =
  forwardAgentEvent("coding", ticketId, event),
```

### Manager agent (`src/scriptorium/manager_agent.nim`)

Current handler (around line 80):
```nim
onEvent: proc(event: AgentStreamEvent) =
  if event.kind == agentEventTool:
    logDebug(&"manager[{areaId}]: {event.text}"),
```

Replace with:
```nim
onEvent: proc(event: AgentStreamEvent) =
  forwardAgentEvent("manager", areaId, event),
```

### Architect agent (`src/scriptorium/architect_agent.nim`)

Current handler (around line 499):
```nim
onEvent: proc(event: AgentStreamEvent) =
  if event.kind == agentEventTool:
    logDebug(fmt"architect: {event.text}"),
```

Replace with:
```nim
onEvent: proc(event: AgentStreamEvent) =
  forwardAgentEvent("architect", "areas", event),
```

Note: The architect currently has no identifier — use the ticketId that is already passed to the function (e.g. `"areas"` for area generation, or the actual ticketId for plan/do passes). Check each call site in `architect_agent.nim` to use the appropriate identifier.

### Review agent (`src/scriptorium/merge_queue.nim`)

Current handler (around line 276):
```nim
onEvent: proc(event: AgentStreamEvent) =
  if event.kind == agentEventTool:
    logDebug(fmt"review[{item.ticketId}]: {event.text}")
  elif event.kind == agentEventMessage:
    ...
```

Replace the tool logging with `forwardAgentEvent("review", item.ticketId, event)`, but **preserve** the existing `agentEventMessage` handling that captures review reasoning — that logic is specific to the review agent and must not be removed.

### Import updates

Add `log_forwarding` to the import block of each modified file. Use bracket syntax per project conventions.

## Acceptance Criteria

- All four agent roles use `forwardAgentEvent` for event logging.
- Review agent retains its `agentEventMessage` reasoning-capture logic alongside the shared forwarding.
- Log output now uses INFO level (not DEBUG) for tool calls and status changes across all roles.
- All agents include both role and identifier in log prefixes.
- File activity lines appear for file-related tool events in all agent roles.
- No behavioral changes beyond log level and format — agent execution logic is untouched.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0099-0091-wire-log-forwarding-into-all-agent-roles

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 11
- reasoning: Straightforward find-and-replace of callback implementations across four files with an import addition each; the replacement code is fully specified and no new logic is needed, just one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0099/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0099/attempt-01.last_message.txt\n
### Agent Last Message
```text
All done. The merge request has been enqueued. Here's a summary of what was changed:

- **coding_agent.nim**: Replaced inline `logDebug` for tool/status events with `forwardAgentEvent("coding", ticketId, event)`
- **manager_agent.nim**: Replaced inline `logDebug` for tool events with `forwardAgentEvent("manager", areaId, event)`
- **architect_agent.nim**: Replaced inline `logDebug` for tool events with `forwardAgentEvent("architect", "areas", event)`
- **merge_queue.nim**: Replaced tool logging with `forwardAgentEvent("review", item.ticketId, event)` while preserving the `agentEventMessage` reasoning-capture logic
- Added `log_forwarding` to the import block of all four files
```

### Agent Stdout Tail
```text
orwardAgentEvent(\"manager\", areaId, event)`\n- **architect_agent.nim**: Replaced inline `logDebug` for tool events with `forwardAgentEvent(\"architect\", \"areas\", event)`\n- **merge_queue.nim**: Replaced tool logging with `forwardAgentEvent(\"review\", item.ticketId, event)` while preserving the `agentEventMessage` reasoning-capture logic\n- Added `log_forwarding` to the import block of all four files","stop_reason":"end_turn","session_id":"d5331ec1-aef0-43a6-9f7a-25a4610fce38","total_cost_usd":0.42068174999999997,"usage":{"input_tokens":17,"cache_creation_input_tokens":24275,"cache_read_input_tokens":316206,"output_tokens":4431,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":24275,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":17,"outputTokens":4431,"cacheReadInputTokens":316206,"cacheCreationInputTokens":24275,"webSearchRequests":0,"costUSD":0.42068174999999997,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"53f87600-e8b4-428d-a819-cb38e94dfea3"}
```
