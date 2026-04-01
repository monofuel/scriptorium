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
