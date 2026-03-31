# 0077 Update init output to match V11 post-init guidance

**Area:** cli-init

**Depends:** 0074, 0075, 0076

## Description

Per V11 §42, §38, §39, §40, the init output must:
- Print a specific message per artifact as it is created:
  - `Created AGENTS.md — edit to match your project conventions.` (§38)
  - `Created Makefile with placeholder targets — replace with real build commands.` (§39)
  - `Created scriptorium.json — configure agent models and harnesses.` (§40)
- After all creation, output a summary with:
  - A "Created artifacts" section listing only items that were actually created (skip items that already existed).
  - A numbered "Next steps" section with instructions to: (1) configure models in scriptorium.json, (2) edit AGENTS.md, (3) run `scriptorium plan`, (4) run `scriptorium run`.
  - Only list next steps relevant to what was created.

## Current behavior

The current output in `src/scriptorium/init.nim` lines 166-197 uses unnumbered bullet-style next steps and different wording.

## Tasks

1. In `src/scriptorium/init.nim`, update the post-init output block (lines 166-197) to:
   - Print per-artifact messages during creation (inline with each creation block).
   - Print a final summary with numbered next steps.
2. Update `tests/integration_cli.nim` test "init output lists created files and next steps" to match the new output format, checking for:
   - The specific per-artifact messages from §38, §39, §40.
   - Numbered next steps.
3. Run `make test` to confirm.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0084-0077-update-init-output-to-match-v11-post-init-guidance

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Straightforward string/output formatting changes in one source file plus updating one integration test to match new expected output, single attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0084/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0084/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes:

- **`src/scriptorium/init.nim`**: Added per-artifact echo messages inline with each creation block (§38, §39, §40). Replaced the summary block with descriptive artifact listings and numbered next steps per §42.
- **`tests/integration_cli.nim`**: Updated the "init output lists created files and next steps" test to check for the new per-artifact messages and numbered next steps format.
```

### Agent Stdout Tail
```text
n- **`src/scriptorium/init.nim`**: Added per-artifact echo messages inline with each creation block (§38, §39, §40). Replaced the summary block with descriptive artifact listings and numbered next steps per §42.\n- **`tests/integration_cli.nim`**: Updated the \"init output lists created files and next steps\" test to check for the new per-artifact messages and numbered next steps format.","stop_reason":"end_turn","session_id":"764c3ac2-a9c0-48eb-b111-6eee395be033","total_cost_usd":0.7339754999999998,"usage":{"input_tokens":28,"cache_creation_input_tokens":35504,"cache_read_input_tokens":714271,"output_tokens":6192,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":35504},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":28,"outputTokens":6192,"cacheReadInputTokens":714271,"cacheCreationInputTokens":35504,"webSearchRequests":0,"costUSD":0.7339754999999998,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"d12a05d9-fdc9-4150-9f44-d0ee9b51d406"}
```
