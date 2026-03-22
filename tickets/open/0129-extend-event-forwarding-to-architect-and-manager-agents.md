# Extend event forwarding to architect and manager agents

**Area:** log-forwarding
**ID:** 0120

## Description

The architect and manager agents should forward stream events to orchestrator logs with the same coverage as the coding agent, providing real-time visibility into all agent activity.

### Current state

- **Architect** (`src/scriptorium/architect_agent.nim`): `runPlanArchitectRequest` accepts an `onEvent` parameter but callers may pass `nil` or a minimal handler.
- **Manager** (`src/scriptorium/manager_agent.nim:98-100`): Only forwards `agentEventTool` events. Does not log status changes.

### Required changes

1. **Architect event forwarding**: Find all call sites of `runPlanArchitectRequest` (in `architect_agent.nim` and `orchestrator.nim`) and ensure they pass an `onEvent` handler that logs tool calls and status changes. Use the format:
   - `architect: tool {event.text}`
   - `architect: status {event.text}`

2. **Manager event forwarding**: Expand the existing `onEvent` in `executeManagerForArea` (line 98-100) to also log status events:
   - `manager[{areaId}]: status {event.text}`
   
   The existing tool logging (`manager[{areaId}]: {event.text}`) should add a `tool ` prefix for consistency: `manager[{areaId}]: tool {event.text}`.

3. All forwarded events should use `logDebug` (same level as coding agent).

### Key files

- `src/scriptorium/architect_agent.nim` — architect `onEvent` wiring
- `src/scriptorium/manager_agent.nim` — manager `onEvent` expansion (line 98-100)
- `src/scriptorium/orchestrator.nim` — may contain architect invocation call sites
- `src/scriptorium/logging.nim` — `logDebug` (read-only reference)

### Notes

- Use `std/strformat` for string formatting (already imported in both files).
- Do not add file activity detection for architect/manager — that is scoped to coding agents only.
- Keep changes minimal: just expand the event kinds handled in each callback.
