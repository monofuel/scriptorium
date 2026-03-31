# 0076 Init creates src/ and docs/ directories on default branch

**Area:** cli-init

## Description

Per V11 §35 (Project Opinions), scriptorium requires `src/`, `tests/`, `docs/` directories. Init already creates `tests/` (via `tests/config.nims`), but does not create `src/` or `docs/`. Init should create these directories with `.gitkeep` files and commit them if they don't already exist.

Existing directories must not be overwritten (same idempotent pattern as AGENTS.md and Makefile).

## Tasks

1. In `src/scriptorium/init.nim`, after the Makefile creation block and before the `scriptorium.json` creation block, add logic to:
   - Check if `src/` exists; if not, create it with a `.gitkeep`, `git add`, and commit.
   - Check if `docs/` exists; if not, create it with a `.gitkeep`, `git add`, and commit.
2. Track `createdSrc` and `createdDocs` booleans for the post-init output.
3. Include these in the "Created" output section and update the "already initialized" check.
4. Add a unit test in `tests/test_init.nim` verifying `src/.gitkeep` and `docs/.gitkeep` exist after init.
5. Add integration tests in `tests/integration_cli.nim` verifying:
   - Init creates `src/` and `docs/` directories.
   - Init skips them if they already exist.
6. Run `make test` to confirm.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0083-0076-init-creates-src-and-docs-directories-on-default-branch

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Well-scoped single-file change following an existing idempotent pattern (AGENTS.md/Makefile), with straightforward test additions to existing test files — one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0083/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0083/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes:

- **`src/scriptorium/init.nim`**: Added `src/` and `docs/` directory creation with `.gitkeep` after the test config block, using `dirExists` checks for idempotency. Updated the "already initialized" condition and output section to include `createdSrc`/`createdDocs`.
- **`tests/test_init.nim`**: Added `testSrcAndDocsCreated` verifying both `.gitkeep` files exist after init.
- **`tests/integration_cli.nim`**: Added two tests — one verifying init creates `src/` and `docs/`, another verifying it skips them when they already exist.
```

### Agent Stdout Tail
```text
dirExists` checks for idempotency. Updated the \"already initialized\" condition and output section to include `createdSrc`/`createdDocs`.\n- **`tests/test_init.nim`**: Added `testSrcAndDocsCreated` verifying both `.gitkeep` files exist after init.\n- **`tests/integration_cli.nim`**: Added two tests — one verifying init creates `src/` and `docs/`, another verifying it skips them when they already exist.","stop_reason":"end_turn","session_id":"fd79c556-5d22-45b8-b6d1-255acf1e5d31","total_cost_usd":1.1827329999999998,"usage":{"input_tokens":39,"cache_creation_input_tokens":41654,"cache_read_input_tokens":1430401,"output_tokens":8280,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":41654,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":39,"outputTokens":8280,"cacheReadInputTokens":1430401,"cacheCreationInputTokens":41654,"webSearchRequests":0,"costUSD":1.1827329999999998,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"9328a13c-1c33-44d6-bace-7e54807ef966"}
```
