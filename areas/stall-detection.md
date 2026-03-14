# Stall Detection And Automatic Continuation

V2 feature: detect coding agent stalls (exit without `submit_pr`) and retry with test-aware continuation prompts.

## Scope

- Stall definition: coding agent turn completes (process exits) without calling the `submit_pr` MCP tool.
- On stall, orchestrator automatically retries with a continuation prompt containing:
  - Full original ticket content.
  - Reminder to continue working and call `submit_pr` when done.
- Retries use existing bounded retry mechanism (`maxAttempts` in `AgentRunRequest`).
- Continuation prompt is distinct from initial prompt — indicates this is a retry after a stall.
- Each stall retry logged with attempt number and ticket ID.
- Test-aware stall detection (augments, does not replace basic stall detection):
  - Before sending continuation prompt, run `make test` in the agent's worktree.
  - Capture exit code and output.
  - If tests fail: include test failure output (truncated if long) and directive to fix failing tests.
  - If tests pass: include note that tests pass and directive to continue and submit.

**Progress-based stall detection (V8, §34):**
- In addition to per-turn stall detection, the orchestrator must detect agents that produce output but make no tool calls within a configurable window.
- "Progress" is defined as the agent calling an MCP tool or producing a tool-call stream event within `agents.coding.progressTimeout` (default 10 minutes).
- If the agent produces stdout (reasoning tokens, status messages) but no tool calls within the window, treat as a stall.
- On progress-based stall:
  - Log: `ticket <id>: agent stalled — output active but no tool calls for <duration>`.
  - Terminate the agent process.
  - Proceed with existing stall continuation flow (pre-retry tests, continuation prompt).
- Progress tracking uses the existing `AgentEventHandler` callback: tool-type events reset the progress timer, other event types do not.
- No-output timeout and hard timeout remain as independent safety nets — progress-based detection is an additional layer.

## Known Limitations

- Per-turn stall detection does not detect in-turn lack of progress (addressed by progress-based detection in V8).
- Test-aware detection runs `make test` only, not `make integration-test`.
- Coding agent promotions and manager-driven retries are out of scope.
- Progress-based stall detection relies on tool-call events from the harness stream; if a harness does not emit tool events, the no-output timeout remains the only stall detector.

## Spec References

- Section 11: Stall Detection And Automatic Continuation (V2).
- Section 12: Test-Aware Stall Detection (V2).
- Section 34: Agent Crash Recovery — progress-based stall detection (V8).
