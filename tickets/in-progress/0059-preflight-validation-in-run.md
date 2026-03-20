# Pre-Flight Validation In scriptorium run

**Area:** cli-init

## Problem

`scriptorium run` has no pre-flight checks. If required files or branches are
missing, the orchestrator silently waits or fails with unclear errors.

## Requirements

- Before starting the orchestrator loop, validate:
  1. `scriptorium/plan` branch exists.
  2. `AGENTS.md` exists in the repo root.
  3. `Makefile` exists in the repo root.
  4. Required make targets exist (at minimum `test`).
  5. Agent binary is available (e.g., `codex` or configured harness binary).
  6. Agent auth is configured (check for API keys or credential files).
- On failure, print a clear error message explaining what is missing and how
  to fix it (e.g., "Run `scriptorium init` first").
- Exit with non-zero status on validation failure.

## Files To Change

- `src/scriptorium.nim` or `src/scriptorium/orchestrator.nim` — add pre-flight checks.
- `tests/integration_cli.nim` or new test — verify validation errors.

## Acceptance Criteria

- `scriptorium run` exits with a clear error if plan branch is missing.
- `scriptorium run` exits with a clear error if AGENTS.md is missing.
- `scriptorium run` exits with a clear error if Makefile or required targets are missing.
- `scriptorium run` warns or errors if agent binary/auth is not found.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0059-preflight-validation-in-run

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Adding 6 sequential validation checks in one module with clear error messages is straightforward logic, but requires touching orchestrator code and writing integration tests to cover each failure case, fitting a single-attempt multi-file change.

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Six sequential validation checks in the orchestrator with clear error messages plus integration tests covering each failure case — straightforward logic but multi-file with moderate test surface.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0059-preflight-validation-in-run/.scriptorium/logs/0059/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0059-preflight-validation-in-run/.scriptorium/logs/0059/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Here's what was implemented:

**`src/scriptorium/orchestrator.nim`** — Added `preflightValidation*` proc called from `runOrchestrator` before `initLog`. It validates:
1. `scriptorium/plan` branch exists
2. `AGENTS.md` exists in repo root
3. `Makefile` exists in repo root
4. Makefile contains a `test:` target
5. Agent binary (codex/claude/typoi based on config) is in PATH
6. API credentials are set (warning only, not a hard error)

On failure, prints clear error messages and exits with non-zero status.

**`tests/integration_cli.nim`** — Added 4 integration tests verifying each hard-failure case via the compiled CLI binary.
```

### Agent Stdout Tail
```text
le` exists in repo root\n4. Makefile contains a `test:` target\n5. Agent binary (codex/claude/typoi based on config) is in PATH\n6. API credentials are set (warning only, not a hard error)\n\nOn failure, prints clear error messages and exits with non-zero status.\n\n**`tests/integration_cli.nim`** — Added 4 integration tests verifying each hard-failure case via the compiled CLI binary.","stop_reason":"end_turn","session_id":"25a49845-2fc3-4b2d-93d2-a34b1aff86fd","total_cost_usd":1.0044970000000002,"usage":{"input_tokens":1357,"cache_creation_input_tokens":57302,"cache_read_input_tokens":947149,"output_tokens":6640,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":57302},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":1357,"outputTokens":6640,"cacheReadInputTokens":947149,"cacheCreationInputTokens":57302,"webSearchRequests":0,"costUSD":1.0044970000000002,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"8a2b985a-770a-4ba6-98b9-274a6f1fbc24"}
```

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0059-preflight-validation-in-run/.scriptorium/logs/0059/attempt-02.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0059-preflight-validation-in-run/.scriptorium/logs/0059/attempt-02.last_message.txt\n
### Agent Last Message
```text
PR submitted for ticket 0059. The preflight validation was already implemented and tests were passing — just needed to call `submit_pr`.
```

### Agent Stdout Tail
```text
s":1},"context_management":null},"parent_tool_use_id":null,"session_id":"444bff75-5a72-4a43-9062-fe08ece19897","uuid":"e4b05d6e-c916-4ad4-bfed-9d5700051a06"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":77335,"duration_api_ms":17309,"num_turns":3,"result":"PR submitted for ticket 0059. The preflight validation was already implemented and tests were passing — just needed to call `submit_pr`.","stop_reason":"end_turn","session_id":"444bff75-5a72-4a43-9062-fe08ece19897","total_cost_usd":0.0891295,"usage":{"input_tokens":7,"cache_creation_input_tokens":11266,"cache_read_input_tokens":17714,"output_tokens":393,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":11266},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":7,"outputTokens":393,"cacheReadInputTokens":17714,"cacheCreationInputTokens":11266,"webSearchRequests":0,"costUSD":0.0891295,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"4523e723-1ed1-4f8b-8bb1-5007fb889cba"}
```

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 3\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0059-preflight-validation-in-run/.scriptorium/logs/0059/attempt-03.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0059-preflight-validation-in-run/.scriptorium/logs/0059/attempt-03.last_message.txt\n
### Agent Last Message
```text
PR submitted for ticket 0059. The preflight validation was already implemented and committed in the previous attempt — tests pass and the working tree is clean.
```

### Agent Stdout Tail
```text
":null},"parent_tool_use_id":null,"session_id":"6df3e6b4-9a61-4c0c-96d8-edbe4b262b2e","uuid":"9b469f8b-2cb0-4d7b-9509-763f7d49d933"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":78796,"duration_api_ms":18690,"num_turns":5,"result":"PR submitted for ticket 0059. The preflight validation was already implemented and committed in the previous attempt — tests pass and the working tree is clean.","stop_reason":"end_turn","session_id":"6df3e6b4-9a61-4c0c-96d8-edbe4b262b2e","total_cost_usd":0.07526525,"usage":{"input_tokens":56,"cache_creation_input_tokens":7185,"cache_read_input_tokens":33358,"output_tokens":536,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":7185},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":56,"outputTokens":536,"cacheReadInputTokens":33358,"cacheCreationInputTokens":7185,"webSearchRequests":0,"costUSD":0.07526525,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"48e6cc56-3148-4ef1-89d3-b8bee9733cc8"}
```

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Six sequential validation checks in orchestrator with clear error messages plus integration tests — straightforward logic but multi-file with moderate test surface, confirmed by successful single-attempt completion.
