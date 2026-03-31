# 0075 Update Makefile template with required make targets

**Area:** cli-init

## Description

Per V11 §39 and §35, the starter Makefile must include `test`, `integration-test`, `e2e-test`, and `build` targets that exit 0. The current template only has `test` and `build`.

**Current template** (`src/scriptorium/init.nim` line 12):
```makefile
.PHONY: test build

test:
	@echo "no tests configured"

build:
	@echo "no build configured"
```

**Required template:**
```makefile
.PHONY: test integration-test e2e-test build

test:
	@echo "no tests configured"

integration-test:
	@echo "no integration tests configured"

e2e-test:
	@echo "no e2e tests configured"

build:
	@echo "no build configured"
```

## Tasks

1. Update `MakefileTemplate` in `src/scriptorium/init.nim` to include `integration-test` and `e2e-test` targets.
2. Update the integration test in `tests/integration_cli.nim` ("init creates Makefile with placeholder targets when missing") to also check for `integration-test:` and `e2e-test:` in the generated content.
3. Run `make test` to confirm tests pass.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0082-0075-update-makefile-template-with-required-make-targets

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 10
- reasoning: Two-file change with exact before/after provided: update a string constant in init.nim and add two substring checks in the integration test, single attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0082/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0082/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes:
- **`src/scriptorium/init.nim`**: Added `integration-test` and `e2e-test` targets to `MakefileTemplate`, matching the required order from the ticket.
- **`tests/integration_cli.nim`**: Added assertions for the new targets in the Makefile creation test.

Resolved a rebase conflict where master had the targets in a different order (build before integration-test/e2e-test) — kept the ticket-specified order.
```

### Agent Stdout Tail
```text
 **`src/scriptorium/init.nim`**: Added `integration-test` and `e2e-test` targets to `MakefileTemplate`, matching the required order from the ticket.\n- **`tests/integration_cli.nim`**: Added assertions for the new targets in the Makefile creation test.\n\nResolved a rebase conflict where master had the targets in a different order (build before integration-test/e2e-test) — kept the ticket-specified order.","stop_reason":"end_turn","session_id":"9abdc476-89b7-4ac7-bc0f-ce5a29716ef4","total_cost_usd":0.5655425000000001,"usage":{"input_tokens":30,"cache_creation_input_tokens":20910,"cache_read_input_tokens":616510,"output_tokens":5058,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":20910,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":30,"outputTokens":5058,"cacheReadInputTokens":616510,"cacheCreationInputTokens":20910,"webSearchRequests":0,"costUSD":0.5655425000000001,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"906cabc1-70f8-48f9-8e65-2229db08dd00"}
```
