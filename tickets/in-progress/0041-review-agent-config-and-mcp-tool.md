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

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0041-review-agent-config-and-mcp-tool/.scriptorium/logs/0041/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0041-review-agent-config-and-mcp-tool/.scriptorium/logs/0041/attempt-01.last_message.txt\n
### Agent Last Message
```text
Changes committed and submitted. Here's what was done:

**config.nim:**
- Added `reviewer*: AgentConfig` to `AgentConfigs`
- Initialized `reviewer` with `defaultAgentConfig()` in `defaultConfig()`
- Added `mergeAgentConfig` call for reviewer in `loadConfig()`
- Harness inference applies automatically via existing `mergeAgentConfig` logic

**orchestrator.nim:**
- Added `ReviewActionMaxBytes`/`ReviewFeedbackMaxBytes` constants and shared buffers
- Added `recordReviewDecision(action, feedback)` and `consumeReviewDecision()` thread-safe procs
- Registered `submit_review` MCP tool with `action` (enum: approve/request_changes) and optional `feedback` schema
- Handler validates action enum, requires feedback for `request_changes`, stores decision via shared state

**Tests (3 new):**
- Reviewer config parsed from `scriptorium.json`
- `inferHarness` works for reviewer-style model names
- `submit_review` tool registered, handler stores/validates decisions correctly
```

### Agent Stdout Tail
```text
stered `submit_review` MCP tool with `action` (enum: approve/request_changes) and optional `feedback` schema\n- Handler validates action enum, requires feedback for `request_changes`, stores decision via shared state\n\n**Tests (3 new):**\n- Reviewer config parsed from `scriptorium.json`\n- `inferHarness` works for reviewer-style model names\n- `submit_review` tool registered, handler stores/validates decisions correctly","stop_reason":"end_turn","session_id":"b154d7b6-0b6d-4816-8b77-a77de795e30f","total_cost_usd":1.02233675,"usage":{"input_tokens":34,"cache_creation_input_tokens":40585,"cache_read_input_tokens":1090821,"output_tokens":8924,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":40585,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":34,"outputTokens":8924,"cacheReadInputTokens":1090821,"cacheCreationInputTokens":40585,"webSearchRequests":0,"costUSD":1.02233675,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"d7117c0e-6b9b-4764-99fb-a3b05fa7928d"}
```
