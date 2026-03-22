# 0122 — Wire log-forwarding into architect, manager, and review agents

**Area:** log-forwarding
**Depends:** 0120

## Summary

Apply the same `forwardAgentEvent` helper to the architect, manager, and review agent event handlers for consistent log forwarding across all agent types.

## Details

Update the `onEvent` handlers in these three files to use `forwardAgentEvent`:

### `src/scriptorium/architect_agent.nim` (around line 470)

Replace:
```nim
onEvent: proc(event: AgentStreamEvent) =
  if event.kind == agentEventTool:
    logDebug(fmt"architect: {event.text}"),
