# Coding agent log forwarding event handler

**Area:** log-forwarding
**ID:** 0118

## Description

Extract the inline `onEvent` callback in `src/scriptorium/coding_agent.nim` (lines 190-194) into a named proc and add file activity detection from tool events.

### Current state

The coding agent's `onEvent` callback logs tool calls and status changes at DEBUG level:
```nim
onEvent: proc(event: AgentStreamEvent) =
  if event.kind == agentEventTool:
    logDebug(fmt"coding[{ticketId}]: {event.text}")
  elif event.kind == agentEventStatus:
    logDebug(fmt"coding[{ticketId}]: status {event.text}"),
