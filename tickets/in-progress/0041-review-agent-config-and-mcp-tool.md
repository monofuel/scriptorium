# Review Agent Config And submit_review MCP Tool

**Area:** agent-execution

## Problem

The review agent role is not yet implemented. The first step is adding `agents.reviewer` config support and the `submit_review` MCP tool.

## Requirements

### Config changes (`config.nim`)

- Add `reviewer` field to `AgentConfigs` object (same type as `architect`, `coding`, `manager`).
- Initialize `reviewer` with `defaultAgentConfig()` in `defaultConfig()`.
- Merge `reviewer` config in `loadConfig()`.
- Model-prefix harness inference applies to reviewer the same as other roles.

### MCP tool (`orchestrator.nim`)

- Register a `submit_review` MCP tool on the orchestrator HTTP server alongside `submit_pr`.
- Input schema:
  - `action`: string, required, enum `["approve", "request_changes"]`.
  - `feedback`: string, optional (required when action is `request_changes`).
- Tool handler:
  - Store the review decision in a thread-safe shared variable (similar to `submitPrSummary`).
  - Return confirmation JSON.
- Add shared state procs: `recordReviewDecision(action, feedback)` and `consumeReviewDecision()` returning a tuple or object with action and feedback.

### Tests

- Unit test that `agents.reviewer` config is parsed from `scriptorium.json`.
- Unit test that `inferHarness` works for reviewer models.
- Unit test that `submit_review` tool is registered and handler stores decision.

## Acceptance Criteria

- `scriptorium.json` with `agents.reviewer.{harness, model, reasoningEffort}` is parsed correctly.
- `submit_review` MCP tool is registered and callable.
- Review decision stored and consumable via thread-safe procs.
- Existing tests still pass.

## Spec References

- Section 21: Review Agent (V4).

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0041-review-agent-config-and-mcp-tool

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 35
- reasoning: Requires parallel changes in config parsing and MCP tool registration following well-established patterns from existing agent roles (architect, coding, manager), plus thread-safe shared state procs and three unit tests.
