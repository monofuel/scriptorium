# Improved Post-Init Output

**Area:** cli-init
**Depends:** 0054, 0056, 0057, 0058

## Problem

Current post-init output is minimal — it only shows the plan branch name and
two next-step commands. It does not list the files that were created or provide
guidance on configuring the generated files.

## Requirements

- After init completes, list all files and branches that were created:
  - Plan branch and its directory structure.
  - AGENTS.md (if generated).
  - Makefile (if generated).
  - scriptorium.json (if generated).
  - spec.md placeholder.
- Provide next-step guidance:
  - Edit AGENTS.md to describe your project.
  - Edit scriptorium.json to configure models and harness.
  - Edit Makefile to set up real test/build targets.
  - Run `scriptorium plan` to build your spec.
  - Run `scriptorium run` to start the orchestrator.
- Update the spec.md placeholder text to reference AGENTS.md.

## Files To Change

- `src/scriptorium/init.nim` — expand post-init output, update spec.md placeholder.
- `tests/integration_cli.nim` — verify expanded output.

## Acceptance Criteria

- Post-init output lists every created file.
- Post-init output includes actionable next steps for each generated file.
- spec.md placeholder references AGENTS.md.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0060-improved-post-init-output

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Straightforward string formatting changes in init.nim to expand output messages and update a placeholder, plus a test assertion update — single-file logic with no complexity.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0060-improved-post-init-output/.scriptorium/logs/0060/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0060-improved-post-init-output/.scriptorium/logs/0060/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes:

- **`src/scriptorium/init.nim`** — Expanded the post-init output to show a "Created:" section listing the plan branch, its directories, spec.md, and any generated files (AGENTS.md, Makefile, scriptorium.json). Added per-file next-step guidance. Updated `SpecPlaceholder` to reference AGENTS.md.
- **`tests/integration_cli.nim`** — Added two tests: one verifying the expanded CLI output contains all expected file listings and next steps, and one verifying spec.md references AGENTS.md.
```

### Agent Stdout Tail
```text
g the plan branch, its directories, spec.md, and any generated files (AGENTS.md, Makefile, scriptorium.json). Added per-file next-step guidance. Updated `SpecPlaceholder` to reference AGENTS.md.\n- **`tests/integration_cli.nim`** — Added two tests: one verifying the expanded CLI output contains all expected file listings and next steps, and one verifying spec.md references AGENTS.md.","stop_reason":"end_turn","session_id":"b6b5dd5a-ebb0-46c2-a1dd-1de59aa0071e","total_cost_usd":0.34910399999999997,"usage":{"input_tokens":4137,"cache_creation_input_tokens":28410,"cache_read_input_tokens":179413,"output_tokens":2446,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":28410},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":4137,"outputTokens":2446,"cacheReadInputTokens":179413,"cacheCreationInputTokens":28410,"webSearchRequests":0,"costUSD":0.34910399999999997,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"ae4a6a1a-ed4c-45d7-a9e3-1664f8e6260a"}
```
