# 0074 — Set logRoot for coding agent

**Area:** log-persistence

## Problem

The coding agent's `AgentRunRequest` does not set `logRoot`, so JSONL logs are written inside the ticket worktree under `<worktree>/.scriptorium/logs/<ticketId>/`. When the worktree is cleaned up after merge, these logs are lost.

## Task

In `src/scriptorium/coding_agent.nim`, in the `executeAssignedTicket` function (around line 176), add the `logRoot` field to the `AgentRunRequest`:

```nim
logRoot: repoPath / ManagedStateDirName / PlanLogDirName / "coder",

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0076-0074-set-logroot-for-coding-agent

## Prediction
- predicted_difficulty: trivial
- predicted_duration_minutes: 5
- reasoning: Single-line addition of a logRoot field to an existing record literal in one file, with the exact code provided in the ticket.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0076-0074-set-logroot-for-coding-agent/.scriptorium/logs/0076/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0076-0074-set-logroot-for-coding-agent/.scriptorium/logs/0076/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Added `logRoot: repoPath / ManagedStateDirName / PlanLogDirName / "coder"` to the `AgentRunRequest` in `coding_agent.nim` and imported `architect_agent` for the `PlanLogDirName` constant. Build compiles cleanly.
```

### Agent Stdout Tail
```text
620-91dd-3001deaf3378","uuid":"a16a714a-1c4f-4f9e-9571-34016ef2c115"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":74096,"duration_api_ms":71152,"num_turns":15,"result":"Done. Added `logRoot: repoPath / ManagedStateDirName / PlanLogDirName / \"coder\"` to the `AgentRunRequest` in `coding_agent.nim` and imported `architect_agent` for the `PlanLogDirName` constant. Build compiles cleanly.","stop_reason":"end_turn","session_id":"22795ca6-8222-4620-91dd-3001deaf3378","total_cost_usd":0.2416735,"usage":{"input_tokens":18,"cache_creation_input_tokens":14760,"cache_read_input_tokens":169817,"output_tokens":2577,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":14760},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":18,"outputTokens":2577,"cacheReadInputTokens":169817,"cacheCreationInputTokens":14760,"webSearchRequests":0,"costUSD":0.2416735,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"733cdb5d-5183-4249-9882-744a929d52ad"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 14s

## Merge Queue Failure
- Summary: Set logRoot on the coding agent's AgentRunRequest so JSONL logs are written to `<repo>/.scriptorium/logs/coder/` instead of inside the ticket worktree. This prevents logs from being lost when the worktree is cleaned up after merge.\n- Failed gate: make integration-test\n
### Merge Output
```text
Already up to date.
```

### Quality Check Output
```text
g... 3/5 (unexpected status 401 Unauthorized: Incorrect API key provided: disabled. You can find your API key at https://platform.openai.com/account/api-keys., url: https://api.openai.com/v1/responses, cf-ray: 9e07d8b679a32309-ORD, request id: req_b67079261b8c4096acf06d087da4bc46)"}
{"type":"error","message":"Reconnecting... 4/5 (unexpected status 401 Unauthorized: Incorrect API key provided: disabled. You can find your API key at https://platform.openai.com/account/api-keys., url: https://api.openai.com/v1/responses, cf-ray: 9e07d8bc8e2f381e-ORD, request id: req_fce0496a36154d2f897016f353f2ba10)"}
{"type":"error","message":"Reconnecting... 5/5 (unexpected status 401 Unauthorized: Incorrect API key provided: disabled. You can find your API key at https://platform.openai.com/account/api-keys., url: https://api.openai.com/v1/responses, cf-ray: 9e07d8c7ce5561dc-ORD, request id: req_cb592773259d46fb9460069b38923772)"}
{"type":"error","message":"unexpected status 401 Unauthorized: Incorrect API key provided: disabled. You can find your API key at https://platform.openai.com/account/api-keys., url: https://api.openai.com/v1/responses, cf-ray: 9e07d8dd7bc8acae-ORD, request id: req_319e84d3cfbf4964b6bad762b4b20a39"}
{"type":"turn.failed","error":{"message":"unexpected status 401 Unauthorized: Incorrect API key provided: disabled. You can find your API key at https://platform.openai.com/account/api-keys., url: https://api.openai.com/v1/responses, cf-ray: 9e07d8dd7bc8acae-ORD, request id: req_319e84d3cfbf4964b6bad762b4b20a39"}}
Warning: no last agent message; wrote empty content to /tmp/scriptorium_integration_codex_mcp_FIZx9sgO/logs/integration-codex-mcp/attempt-01.last_message.txt
 [AssertionDefect]
  [FAILED] real codex MCP tool call against live server
Error: execution of an external program failed: '/home/scriptorium/.cache/nim/integration_codex_harness_d/integration_codex_harness_F38ED76A4C7B6968847B7C1F705BC71DEF66802F'
make: *** [Makefile:35: integration-test] Error 1
```

## Metrics
- wall_time_seconds: 702
- coding_wall_seconds: 75
- test_wall_seconds: 0
- attempt_count: 1
- outcome: reopened
- failure_reason: test_failure
- model: claude-opus-4-6
- stdout_bytes: 75296

## Post-Analysis
- actual_difficulty: hard
- prediction_accuracy: underestimated
- brief_summary: Predicted trivial, actual was hard with 1 attempt(s) in 11m42s.

## Prediction
- predicted_difficulty: trivial
- predicted_duration_minutes: 5
- reasoning: Single-line addition of a logRoot field to an existing record literal with exact code provided; the merge queue failure was due to an unrelated OpenAI API key issue in integration tests, not a code defect.
