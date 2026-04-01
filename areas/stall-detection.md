# Stall Detection And Automatic Continuation

V2 feature: detect agent stalls across all roles and retry with continuation prompts. Test-aware continuation for coding agents.

## Scope

**Universal stall detection (§11) — applies to all agent roles:**
- A "stall" is defined per role as an agent turn completing (process exits) without its expected completion signal:
  - **Coding agent:** exits without calling the `submit_pr` MCP tool.
  - **Review agent:** exits without calling the `submit_review` MCP tool (stall defaults to approval, see review-agent area).
  - **Manager agent:** exits without producing any ticket files in `tickets/open/`, or exceeds its hard timeout.
  - **Architect agent:** exits without producing or updating any area files in `areas/`, or exceeds its hard timeout.
- On stall, orchestrator automatically retries with a continuation prompt containing:
  - Full original prompt content (ticket content for coding/review, area list for manager, spec for architect).
  - Reminder to continue working and complete the expected action.
- Retries use existing bounded retry mechanism (`maxAttempts` in `AgentRunRequest`).
- Continuation prompt is distinct from initial prompt — indicates this is a retry after a stall.
- Each stall retry logged with attempt number, agent role, and relevant identifier (ticket ID, area ID, etc.).
- Hard timeout and no-output timeout apply to all agent roles as baseline safety nets, configurable per role via `agents.<role>.hardTimeout` and `agents.<role>.noOutputTimeout` in `scriptorium.json`.

**Test-aware stall detection (§12, coding agents only):**
- Before sending the coding agent continuation prompt, run `make test` in the agent's worktree.
- Capture exit code and output.
- If tests fail: include test failure output (truncated if long) and directive to fix failing tests before submitting.
- If tests pass: include note that tests pass and directive to continue and submit.
- Test-aware detection is specific to coding agents — manager and architect agents operate on the plan branch and do not have a meaningful `make test` gate. Review agents also skip this step.

**Progress-based stall detection (V8, §34) — applies to all agent roles:**
- In addition to per-turn stall detection, the orchestrator must detect agents that produce output but make no tool calls within a configurable window.
- "Progress" is defined as the agent calling an MCP tool or producing a tool-call stream event within `agents.<role>.progressTimeout` (configurable per role, default 10 minutes).
- If the agent produces stdout (reasoning tokens, status messages) but no tool calls within the window, treat as a stall.
- On progress-based stall:
  - Log: `<role> <id>: agent stalled — output active but no tool calls for <duration>`.
  - Terminate the agent process.
  - Proceed with existing stall continuation flow: for coding agents, run pre-retry tests (§12) then send continuation prompt; for other roles, send the role-appropriate continuation prompt directly.
- Progress tracking uses the existing `AgentEventHandler` callback: tool-type events reset the progress timer, other event types do not.
- No-output timeout and hard timeout remain as independent safety nets — progress-based detection is an additional layer.

## Known Limitations

- Per-turn stall detection does not detect in-turn lack of progress (addressed by progress-based detection in V8).
- Test-aware detection runs `make test` only, not `make integration-test`.
- Manager and architect stall detection checks for output file creation, which may miss partial or malformed output — the orchestrator does not validate content quality at the stall detection level.
- Progress-based stall detection relies on tool-call events from the harness stream; if a harness does not emit tool events, the no-output timeout remains the only stall detector.

## Spec References

- Section 11: Stall Detection And Automatic Continuation (V2).
- Section 12: Test-Aware Stall Detection (V2).
- Section 34: Agent Crash Recovery — progress-based stall detection (V8).
