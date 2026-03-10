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
