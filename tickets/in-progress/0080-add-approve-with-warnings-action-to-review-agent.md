<!-- ticket: 0074-approve-with-warnings-action.md -->
# Add `approve_with_warnings` action to review agent

**Area:** review-agent
**Difficulty:** medium

## Problem

The `submit_review` MCP tool in `src/scriptorium/mcp_server.nim` only supports two actions: `approve` and `request_changes`. The spec (Section 9) and area definition require a third action: `approve_with_warnings`, which accepts the changes but logs warnings for minor style issues.

## Requirements

1. **MCP tool update** (`src/scriptorium/mcp_server.nim`):
   - Add `"approve_with_warnings"` to the `enum` array in the `submit_review` tool's `inputSchema`.
   - Update the validation in `submitReviewHandler` to accept `approve_with_warnings` as a valid action.
   - When `action` is `approve_with_warnings`, `feedback` should be accepted (warnings text) but not required.

2. **Merge queue handling** (`src/scriptorium/merge_queue.nim`):
   - In `runReviewAgent`, handle `approve_with_warnings` as a successful review (merge proceeds).
   - Log at INFO level: `ticket <id>: review approved with warnings`.
   - Append a structured review note to the ticket markdown that includes the warnings text from `feedback`. Use a format like:

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0080-add-approve-with-warnings-action-to-review-agent

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Two-file change adding a new enum variant and a simple branch in the review handler — the logic mirrors existing approve/request_changes paths with no complex integration risk.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0080-add-approve-with-warnings-action-to-review-agent/.scriptorium/logs/0080/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0080-add-approve-with-warnings-action-to-review-agent/.scriptorium/logs/0080/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes in two files:

- **`src/scriptorium/mcp_server.nim`**: Added `"approve_with_warnings"` to the enum array and updated validation to accept it as a valid action (feedback accepted but not required).
- **`src/scriptorium/merge_queue.nim`**: Added `approve_with_warnings` branch in `runReviewAgent` — logs at INFO level (`ticket <id>: review approved with warnings`), generates a structured review note with `**Review:** approved with warnings` and optional `**Warnings:**` section from feedback. The action falls through to merge (same as approve) since `processMergeQueue` only blocks on `request_changes`.
```

### Agent Stdout Tail
```text
m/merge_queue.nim`**: Added `approve_with_warnings` branch in `runReviewAgent` — logs at INFO level (`ticket <id>: review approved with warnings`), generates a structured review note with `**Review:** approved with warnings` and optional `**Warnings:**` section from feedback. The action falls through to merge (same as approve) since `processMergeQueue` only blocks on `request_changes`.","stop_reason":"end_turn","session_id":"01c85660-504e-4c03-9173-37fea877e27c","total_cost_usd":0.7688397499999999,"usage":{"input_tokens":9613,"cache_creation_input_tokens":49269,"cache_read_input_tokens":633387,"output_tokens":3846,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":49269},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":9613,"outputTokens":3846,"cacheReadInputTokens":633387,"cacheCreationInputTokens":49269,"webSearchRequests":0,"costUSD":0.7688397499999999,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"67be272b-f160-4d2d-a31b-30bbf6330066"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 29s

## Merge Queue Failure
- Summary: Add approve_with_warnings action to review agent. Updated MCP tool schema enum and validation in mcp_server.nim, and added approve_with_warnings handling in merge_queue.nim (INFO log, structured review note with optional warnings text, merge proceeds as with approve).\n- Failed gate: make integration-test\n
### Merge Output
```text
Already up to date.
```

### Quality Check Output
```text
g... 3/5 (unexpected status 401 Unauthorized: Incorrect API key provided: disabled. You can find your API key at https://platform.openai.com/account/api-keys., url: https://api.openai.com/v1/responses, cf-ray: 9e07dd3b8a4df85d-ORD, request id: req_504f27b365f44823934464fb87a2d95f)"}
{"type":"error","message":"Reconnecting... 4/5 (unexpected status 401 Unauthorized: Incorrect API key provided: disabled. You can find your API key at https://platform.openai.com/account/api-keys., url: https://api.openai.com/v1/responses, cf-ray: 9e07dd41aedf13ec-ORD, request id: req_eae4eb81051244e0b15bc5d906f58468)"}
{"type":"error","message":"Reconnecting... 5/5 (unexpected status 401 Unauthorized: Incorrect API key provided: disabled. You can find your API key at https://platform.openai.com/account/api-keys., url: https://api.openai.com/v1/responses, cf-ray: 9e07dd4c8d98c0b2-ORD, request id: req_29fc00fcce9b4df4acc55f749fca35b2)"}
{"type":"error","message":"unexpected status 401 Unauthorized: Incorrect API key provided: disabled. You can find your API key at https://platform.openai.com/account/api-keys., url: https://api.openai.com/v1/responses, cf-ray: 9e07dd614fd7f851-ORD, request id: req_c6e529d6de064e2fb1149893518eea8e"}
{"type":"turn.failed","error":{"message":"unexpected status 401 Unauthorized: Incorrect API key provided: disabled. You can find your API key at https://platform.openai.com/account/api-keys., url: https://api.openai.com/v1/responses, cf-ray: 9e07dd614fd7f851-ORD, request id: req_c6e529d6de064e2fb1149893518eea8e"}}
Warning: no last agent message; wrote empty content to /tmp/scriptorium_integration_codex_mcp_pUE5gHzb/logs/integration-codex-mcp/attempt-01.last_message.txt
 [AssertionDefect]
  [FAILED] real codex MCP tool call against live server
Error: execution of an external program failed: '/home/scriptorium/.cache/nim/integration_codex_harness_d/integration_codex_harness_6E5DE5E70494C66B2DDFEC3BF9DEB779C3571B3E'
make: *** [Makefile:35: integration-test] Error 1
```

## Metrics
- wall_time_seconds: 855
- coding_wall_seconds: 486
- test_wall_seconds: 0
- attempt_count: 1
- outcome: reopened
- failure_reason: test_failure
- model: claude-opus-4-6
- stdout_bytes: 291318

## Post-Analysis
- actual_difficulty: hard
- prediction_accuracy: underestimated
- brief_summary: Predicted easy, actual was hard with 1 attempt(s) in 14m15s.

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Two-file change adding a third enum variant and a simple conditional branch mirroring existing approve/request_changes paths — the integration test failure was an unrelated OpenAI API key issue, not a code defect.
