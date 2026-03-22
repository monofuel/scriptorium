# 0120 — Log-forwarding helper for agent stream events

**Area:** log-forwarding

## Summary

Create a shared proc that receives `AgentStreamEvent` objects and forwards meaningful events to orchestrator logs at appropriate levels. This centralizes the event-to-log mapping so all agent types can reuse it.

## Details

Add a new proc in `src/scriptorium/agent_runner.nim` (where `AgentStreamEvent` is already defined):

```nim
proc forwardAgentEvent*(ticketId: string, event: AgentStreamEvent) =
