# 0090 Shared agent log-forwarding helper with file activity detection

**Area:** log-forwarding
**Priority:** medium

## Summary

Create a reusable proc in a new module `src/scriptorium/log_forwarding.nim` that all agent roles can call from their `onEvent` callbacks to forward meaningful stream events to orchestrator logs with a consistent format.

## Requirements

1. **Create `src/scriptorium/log_forwarding.nim`** with a public proc:
   ```nim
   proc forwardAgentEvent*(role: string, identifier: string, event: AgentStreamEvent)
   ```
   - `role`: agent role string (e.g. `"coding"`, `"manager"`, `"architect"`, `"review"`)
   - `identifier`: correlation ID (ticket ID, area ID, etc.)
   - `event`: the normalized `AgentStreamEvent` from `agent_runner.nim`

2. **Event handling logic:**
   - `agentEventTool`: Log at INFO level with prefix `{role}[{identifier}]: tool {event.text}`. Additionally, parse `event.text` to detect file activity (see below) and log a separate file activity line.
   - `agentEventStatus`: Log at INFO level with prefix `{role}[{identifier}]: status {event.text}`.
   - `agentEventHeartbeat`: Skip (do not log — these are high-frequency).
   - `agentEventReasoning`: Skip (too verbose for orchestrator logs).
   - `agentEventMessage`: Skip (final output, not a forwarding concern).

3. **File activity detection from tool events:**
   - Create a helper proc `extractFileActivity*(toolText: string): string` that examines tool event text and returns a file activity summary, or empty string if none detected.
   - Detect common tool patterns: `Read`, `Edit`, `Write`, `Bash` (with file-related args), `edit_file`, `read_file`, `write_file`, `create_file`.
   - For recognized file tools, extract the file path from the argument summary and log: `{role}[{identifier}]: file {read|write} {path}`.
   - Keep extraction best-effort — if the path cannot be parsed, log the tool call only (no file activity line).

4. **Use `logInfo` from `logging.nim`** for forwarded events (not `logDebug`), so they appear in orchestrator logs by default.

5. **Use `&` for format strings** per project conventions. Assign values to variables before interpolation.

6. **Imports:** Use bracket syntax, std/ first, then local modules (`./[agent_runner, logging]`).

7. **Doc comments (`##`)** on every proc.

## Acceptance Criteria

- Module compiles and exports `forwardAgentEvent` and `extractFileActivity`.
- Tool events produce an INFO log line with role and identifier prefix.
- File-related tool events produce an additional file activity log line.
- Status events produce an INFO log line.
- Heartbeat, reasoning, and message events are silently skipped.
- No new event types are invented — only existing `AgentStreamEventKind` values are used.
