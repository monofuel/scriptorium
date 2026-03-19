# Init Generates Starter Makefile

**Area:** cli-init

## Problem

`scriptorium init` does not generate a Makefile. The orchestrator expects
`make test` and other targets to exist, so new projects fail at runtime.

## Requirements

- During init, check if a `Makefile` exists in the target repo root.
- If missing, generate a minimal Makefile with placeholder targets:
  - `test` — placeholder that echoes "no tests configured".
  - `build` — placeholder that echoes "no build configured".
  - Any other targets the orchestrator expects.
- Leave the Makefile uncommitted (or commit on default branch) for user customization.
- Log that the Makefile was created.

## Files To Change

- `src/scriptorium/init.nim` — add Makefile generation step.
- `tests/integration_cli.nim` — verify Makefile is created when missing.

## Acceptance Criteria

- Running `scriptorium init` on a repo without a Makefile creates one with placeholder targets.
- Running `scriptorium init` on a repo that already has a Makefile skips this step.
- Generated Makefile has `test` and `build` targets at minimum.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0057-init-generates-makefile

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 11
- reasoning: Single-file addition of Makefile generation logic in init.nim following the existing pattern for AGENTS.md generation, plus a straightforward integration test — minimal complexity, one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 2\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0057-init-generates-makefile/.scriptorium/logs/0057/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0057-init-generates-makefile/.scriptorium/logs/0057/attempt-02.last_message.txt\n
### Agent Last Message
```text
All work for ticket 0057 is complete and committed:

**Summary of changes (commit `c87e538`):**

- **`src/scriptorium/init.nim`**: Added Makefile generation step during `init`. When no `Makefile` exists, generates one with `.PHONY`, `test`, and `build` placeholder targets. Logs creation to the user.
- **`tests/integration_cli.nim`**: Added two integration tests:
  - "init creates Makefile with placeholder targets when missing" — verifies Makefile is created with `test:` and `build:` targets
  - "init skips Makefile when it already exists" — verifies existing Makefiles are preserved

All 6 integration tests pass. The `submit_pr` MCP tool is not available in this environment — the orchestrator should pick up the committed changes on branch `scriptorium/ticket-0057`.
```

### Agent Stdout Tail
```text
it creates Makefile with placeholder targets when missing\" — verifies Makefile is created with `test:` and `build:` targets\n  - \"init skips Makefile when it already exists\" — verifies existing Makefiles are preserved\n\nAll 6 integration tests pass. The `submit_pr` MCP tool is not available in this environment — the orchestrator should pick up the committed changes on branch `scriptorium/ticket-0057`.","stop_reason":"end_turn","session_id":"ba05ea74-ed39-4293-b9f8-dfc0de7a0e72","total_cost_usd":0.506574,"usage":{"input_tokens":78,"cache_creation_input_tokens":31916,"cache_read_input_tokens":471768,"output_tokens":2833,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":31916},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":78,"outputTokens":2833,"cacheReadInputTokens":471768,"cacheCreationInputTokens":31916,"webSearchRequests":0,"costUSD":0.506574,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"35812564-dfd3-4180-8e4e-5e5d25ba49a6"}
```
