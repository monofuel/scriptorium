# Init Generates scriptorium.json

**Area:** cli-init

## Problem

`scriptorium init` does not generate a `scriptorium.json` config file. Users
must create one manually or rely on in-memory defaults.

## Requirements

- During init, check if `scriptorium.json` exists in the target repo root.
- If missing, generate it using `defaultConfig()` from `config.nim`, serialized
  to JSON.
- Leave the file uncommitted for user customization.
- Log that the file was created.

## Files To Change

- `src/scriptorium/init.nim` — add scriptorium.json generation step.
- `tests/integration_cli.nim` — verify scriptorium.json is created when missing.

## Acceptance Criteria

- Running `scriptorium init` on a repo without scriptorium.json creates one
  with default config values.
- Running `scriptorium init` on a repo that already has scriptorium.json skips this step.
- The generated JSON is valid and parseable by the config loader.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0058-init-generates-scriptorium-json

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 11
- reasoning: Single-file addition to init.nim following established patterns (AGENTS.md and Makefile generation already exist), plus a straightforward integration test assertion — one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0058-init-generates-scriptorium-json/.scriptorium/logs/0058/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0058-init-generates-scriptorium-json/.scriptorium/logs/0058/attempt-01.last_message.txt\n
### Agent Last Message
```text
`submit_pr` is an MCP tool served by the orchestrator's MCP server. It's not available directly in my tool set — the orchestrator should be providing it. Since I can't call the MCP tool directly, the implementation is complete. Let me verify the final state of the changed files.

All work is done:

**Changes made:**

1. **`src/scriptorium/init.nim`** — Added scriptorium.json generation step during init:
   - Imports `jsony` and `defaultConfig` from config module
   - Checks if `scriptorium.json` exists; if missing, writes `defaultConfig()` serialized to JSON
   - File is left uncommitted for user customization
   - Logs creation in the init summary output

2. **`tests/integration_cli.nim`** — Added two integration tests:
   - `init creates scriptorium.json with default config when missing` — verifies the file is created and loadable with correct defaults
   - `init skips scriptorium.json when it already exists` — verifies existing config is preserved

All 8 integration tests pass. The commit is ready on branch `scriptorium/ticket-0058`. The `submit_pr` MCP tool needs to be called by the orchestrator to enqueue for merge.
```

### Agent Stdout Tail
```text
 `init creates scriptorium.json with default config when missing` — verifies the file is created and loadable with correct defaults\n   - `init skips scriptorium.json when it already exists` — verifies existing config is preserved\n\nAll 8 integration tests pass. The commit is ready on branch `scriptorium/ticket-0058`. The `submit_pr` MCP tool needs to be called by the orchestrator to enqueue for merge.","stop_reason":"end_turn","session_id":"890158ee-7700-4ab7-a589-6fb2a3a61ca2","total_cost_usd":0.867085,"usage":{"input_tokens":2243,"cache_creation_input_tokens":38386,"cache_read_input_tokens":939065,"output_tokens":5857,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":38386},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":2243,"outputTokens":5857,"cacheReadInputTokens":939065,"cacheCreationInputTokens":38386,"webSearchRequests":0,"costUSD":0.867085,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"85ed0b64-c2e6-42d8-9f3e-9cc8a6f26347"}
```
