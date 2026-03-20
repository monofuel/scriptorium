# Update E2E Tests To Use scriptorium init

**Area:** cli-init
**Depends:** 0054, 0056, 0057

## Problem

E2E tests in `tests/e2e_euler_live.nim` and integration tests use manual seeding
(calling `runInit()` programmatically and adding files separately) instead of
exercising the `scriptorium init` subcommand. This means the init flow is not
tested end-to-end.

## Requirements

- Update `tests/support/live_integration_support.nim` `initLiveRepo()` to use
  the `scriptorium init` subcommand via CLI invocation instead of calling
  `runInit()` directly.
- Remove manual Makefile/AGENTS.md seeding steps that are now handled by init.
- Ensure e2e tests still pass with the new init flow.
- Keep any test-specific overrides (e.g., custom Makefile targets for Euler
  problems) as post-init modifications.

## Files To Change

- `tests/support/live_integration_support.nim` — update init helper.
- `tests/e2e_euler_live.nim` — remove manual seeding if now redundant.
- `tests/integration_orchestrator_live_submit_pr.nim` — same as above.

## Acceptance Criteria

- E2E tests use `scriptorium init` CLI subcommand for setup.
- Manual seeding of AGENTS.md, Makefile, and scriptorium.json is removed where
  init now handles it.
- All e2e and integration tests pass.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0061-e2e-test-uses-init-subcommand

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Multi-file test refactor across 3 files replacing manual seeding with CLI invocation, moderate integration risk from ensuring existing e2e tests still pass with the new init flow.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0061-e2e-test-uses-init-subcommand/.scriptorium/logs/0061/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0061-e2e-test-uses-init-subcommand/.scriptorium/logs/0061/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Summary of changes to `tests/support/live_integration_support.nim`:

- **`initLiveRepo`**: Now invokes the CLI binary (`scriptorium init <path>`) via `ensureCliBinary()` + `runCmdOrDie()` instead of calling `runInit()` directly
- **`withTempLiveRepo`**: Removed `writeFixtureAgentsFile()` call — AGENTS.md is now created by the `init` subcommand
- **Removed**: `writeFixtureAgentsFile` proc, `AgentsExamplePath` const, `init` import
- **No changes needed** in `e2e_euler_live.nim` or `integration_orchestrator_live_submit_pr.nim` — the test-specific Makefile overrides (`addEulerMakefile`/`addPassingMakefile`) remain as post-init modifications
```

### Agent Stdout Tail
```text
eRepo`**: Removed `writeFixtureAgentsFile()` call — AGENTS.md is now created by the `init` subcommand\n- **Removed**: `writeFixtureAgentsFile` proc, `AgentsExamplePath` const, `init` import\n- **No changes needed** in `e2e_euler_live.nim` or `integration_orchestrator_live_submit_pr.nim` — the test-specific Makefile overrides (`addEulerMakefile`/`addPassingMakefile`) remain as post-init modifications","stop_reason":"end_turn","session_id":"0bb2cbc2-77f1-4c2d-b3a4-1260b1446d98","total_cost_usd":0.72116075,"usage":{"input_tokens":4057,"cache_creation_input_tokens":40607,"cache_read_input_tokens":594214,"output_tokens":5999,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":40607},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":4057,"outputTokens":5999,"cacheReadInputTokens":594214,"cacheCreationInputTokens":40607,"webSearchRequests":0,"costUSD":0.72116075,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"8b1a8023-8a78-4c0d-9de5-d7b6711659c2"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 40s
