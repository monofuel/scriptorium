# 0125 — Coding agent log forwarding

**Area:** log-forwarding

## Summary

Enhance the coding agent's `onEvent` callback in `coding_agent.nim` to forward meaningful stream events to orchestrator logs at INFO level in real time.

## Context

The current callback at `src/scriptorium/coding_agent.nim` lines 190-195 only logs tool and status events at DEBUG level using `logDebug`. The area spec requires INFO-level forwarding of tool calls, file activity, and status changes, prefixed with ticket ID for correlation.

## Tasks

1. In `src/scriptorium/coding_agent.nim`, update the `onEvent` callback in `executeAssignedTicket()` (around line 190):
   - **Tool calls**: Log tool name and argument summary at INFO level. Format: `coding[{ticketId}]: tool {event.text}` (event.text already contains tool name + arg summary from the harness parsers).
   - **File activity**: Detect file-related tools (e.g., tool names containing `edit`, `write`, `read`, `create`) from `agentEventTool` events and log them distinctly. Format: `coding[{ticketId}]: file {event.text}`.
   - **Status changes**: Log status transitions at INFO level. Format: `coding[{ticketId}]: status {event.text}`.
   - **Heartbeat**: Do NOT log heartbeat events (they are noise).
   - **Reasoning/Message**: Do NOT log these — they contain model output that would flood logs.

2. Use `logInfo()` from `src/scriptorium/logging.nim` instead of `logDebug()`.

3. Keep the ticket ID prefix (`coding[{ticketId}]`) for log correlation as currently done.

4. No new event types — use the existing `AgentStreamEventKind` enum (`agentEventHeartbeat`, `agentEventReasoning`, `agentEventTool`, `agentEventStatus`, `agentEventMessage`).

## Verification

- Run `make test` to ensure no regressions.
- Confirm that tool and status events are logged at INFO level (not DEBUG) by reading the callback code.
