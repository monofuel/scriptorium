# 0126 — Manager agent log forwarding

**Area:** log-forwarding

## Summary

Enhance the manager agent's `onEvent` callback in `manager_agent.nim` to forward meaningful stream events to orchestrator logs at INFO level, matching the pattern used for coding agents.

## Context

The current callback at `src/scriptorium/manager_agent.nim` (around line 98-100) only logs tool events at DEBUG level. Apply the same log forwarding pattern as the coding agent: tool calls, file activity, and status changes at INFO level with area/agent prefix.

## Tasks

1. In `src/scriptorium/manager_agent.nim`, update the `onEvent` callback:
   - **Tool calls**: Log at INFO level. Format: `manager[{areaName}]: tool {event.text}`.
   - **File activity**: Detect file-related tools from `agentEventTool` events and log distinctly. Format: `manager[{areaName}]: file {event.text}`.
   - **Status changes**: Log at INFO level. Format: `manager[{areaName}]: status {event.text}`.
   - **Heartbeat/Reasoning/Message**: Do NOT log these.

2. Use `logInfo()` from `src/scriptorium/logging.nim` instead of `logDebug()`.

3. Use the area name (or other identifying context) as the prefix for log correlation, since managers operate per-area rather than per-ticket.

## Verification

- Run `make test` to ensure no regressions.
- Confirm that tool and status events are logged at INFO level by reading the callback code.
