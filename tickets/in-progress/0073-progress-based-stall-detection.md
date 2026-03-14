# Progress-Based Stall Detection

**Area:** stall-detection
**Depends:** 0065

Implement progress-based stall detection that terminates agents producing output but making no tool calls within a configurable window (V8, §34).

## Requirements

### Progress Tracking
- "Progress" is defined as the agent calling an MCP tool or producing a tool-call stream event within `agents.coding.progressTimeout` (default 10 minutes, configured via ticket 0065).
- Track the last tool-call event timestamp using the existing `AgentEventHandler` callback in `AgentRunRequest.onEvent`.
- Tool-type events (`agentEventTool`) reset the progress timer. Other event types (status, output) do not.

### Stall Detection
- If the agent produces stdout (reasoning tokens, status messages) but no tool calls within the configured timeout window, treat as a stall.
- On progress-based stall:
  - Log: `ticket <id>: agent stalled — output active but no tool calls for <duration>`.
  - Terminate the agent process.
  - Proceed with existing stall continuation flow (pre-retry tests, continuation prompt from tickets 0031/0032).

### Independence
- Progress-based detection is an additional layer — it does not replace:
  - No-output timeout (`codingAgentNoOutputTimeoutMs`): fires when agent produces no output at all.
  - Hard timeout (`codingAgentHardTimeoutMs`): fires after absolute time limit.
- All three timeout types operate independently.

## Implementation Notes

- In `coding_agent.nim`, update the `onEvent` callback in `executeAssignedTicket` to track the last tool-call timestamp.
- Add a monitoring mechanism (e.g., a timer check in the event handler or a separate watchdog) that compares current time against last tool-call timestamp.
- When progress timeout fires, set a flag or use the existing timeout mechanism to terminate the agent and trigger stall continuation.
- The harness backends (`harness_codex.nim`, `harness_claude_code.nim`) already emit tool events — no changes needed there.

## Acceptance Criteria

- Agent terminated when it produces output but no tool calls for the configured duration.
- Log message emitted with the stall duration.
- Existing stall continuation flow (test-aware retry) triggered after termination.
- No-output and hard timeouts continue to work independently.
- Unit tests cover: progress timeout fires when only status events received, progress timer resets on tool events, no false trigger when tools are called within window.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0073-progress-based-stall-detection
