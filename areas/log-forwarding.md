# Coding Agent Log Forwarding

Real-time forwarding of meaningful coding agent stream events to orchestrator logs.

## Scope

- During coding agent execution, forward stream events from the agent harness to orchestrator logs in real time.
- Event types surfaced for both claude-code and codex harnesses:
  - Tool calls: log tool name and argument summary (e.g., `agent: tool edit_file src/foo.nim`).
  - File activity: log file reads and writes detected from tool events.
  - Status changes: log agent status transitions (e.g., `agent: thinking`, `agent: executing tool`).
- Uses existing AgentEventHandler callback to receive parsed stream events.
- Log output prefixed with ticket ID for correlation.
- No new event types invented — uses existing heartbeat, reasoning, tool, status, and message categories.

## Spec References

- Section 7: Coding Agent Execution (log forwarding).
