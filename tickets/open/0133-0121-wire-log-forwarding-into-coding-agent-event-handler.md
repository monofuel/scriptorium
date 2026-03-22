# 0121 — Wire log-forwarding into coding agent event handler

**Area:** log-forwarding
**Depends:** 0120

## Summary

Replace the minimal `logDebug`-only event handler in `coding_agent.nim` with a call to the shared `forwardAgentEvent` proc from ticket 0120.

## Details

In `src/scriptorium/coding_agent.nim`, replace lines 190-194:

```nim
onEvent: proc(event: AgentStreamEvent) =
  if event.kind == agentEventTool:
    logDebug(fmt"coding[{ticketId}]: {event.text}")
  elif event.kind == agentEventStatus:
    logDebug(fmt"coding[{ticketId}]: status {event.text}"),
