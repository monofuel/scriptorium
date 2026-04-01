# Agent Log Forwarding

V2 feature: real-time forwarding of meaningful stream events from all agent execution to orchestrator logs.

## Scope

- During all agent execution (coding, manager, architect, and review), forward meaningful stream events from the agent harness to orchestrator logs in real time.
- Event types surfaced for both claude-code (stream-json) and codex (--json) harnesses:
  - Tool calls: log tool name and argument summary (e.g., `agent: tool edit_file src/foo.nim`).
  - File activity: log file reads and writes detected from tool events.
  - Status changes: log agent status transitions (e.g., `agent: thinking`, `agent: executing tool`).
- Uses existing AgentEventHandler callback to receive parsed stream events.
- Log output prefixed with agent role and relevant identifier (ticket ID, area ID, etc.) for correlation.
- No new event types invented — uses existing heartbeat, reasoning, tool, status, and message categories.

## Spec References

- Section 10: Agent Log Forwarding (V2).
