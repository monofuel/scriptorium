# 0075 Add integration-test and e2e-test targets to init Makefile template

**Area:** config-testing

## Summary

The `scriptorium init` command creates a starter Makefile with only `test` and `build` targets. Per V11 §35, all managed projects must also have `integration-test` and optionally `e2e-test` make targets.

## Requirements

1. In `src/scriptorium/init.nim`, update the `MakefileTemplate` constant to include:
   - `integration-test` target (with placeholder `@echo "no integration tests configured"`).
   - `e2e-test` target (with placeholder `@echo "no e2e tests configured"`).
   - Add all four targets to the `.PHONY` declaration.

2. In `tests/test_init.nim`, add or update a test that verifies the Makefile created by `runInit` contains all four required targets: `test`, `build`, `integration-test`, `e2e-test`.

## Notes

- The Makefile template is a `const` string in init.nim. Just extend it with the new targets.
- Keep the template minimal — placeholder echo commands only.
- Existing repos that already ran init will not be affected (init skips files that already exist).

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0079-0075-add-integration-test-and-e2e-test-targets-to-init-makefile-template

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 10
- reasoning: Single-file const string extension in init.nim plus a straightforward test addition in test_init.nim, minimal logic complexity, one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0079/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0079/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes:
- **`src/scriptorium/init.nim`**: Extended `MakefileTemplate` with `integration-test` and `e2e-test` targets (placeholder echo commands) and added them to `.PHONY`.
- **`tests/test_init.nim`**: Added `testMakefileContainsAllTargets` verifying all four targets exist in the generated Makefile.
```

### Agent Stdout Tail
```text
":"result","subtype":"success","is_error":false,"duration_ms":60951,"duration_api_ms":59320,"num_turns":15,"result":"Done. Changes:\n- **`src/scriptorium/init.nim`**: Extended `MakefileTemplate` with `integration-test` and `e2e-test` targets (placeholder echo commands) and added them to `.PHONY`.\n- **`tests/test_init.nim`**: Added `testMakefileContainsAllTargets` verifying all four targets exist in the generated Makefile.","stop_reason":"end_turn","session_id":"987f672d-eb9b-4ad3-8c00-46a56d341943","total_cost_usd":0.37249075,"usage":{"input_tokens":14,"cache_creation_input_tokens":25345,"cache_read_input_tokens":288979,"output_tokens":2781,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":25345,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":14,"outputTokens":2781,"cacheReadInputTokens":288979,"cacheCreationInputTokens":25345,"webSearchRequests":0,"costUSD":0.37249075,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"5fb790b9-59d3-4271-aa20-5807d647cfaa"}
```
