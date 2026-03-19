# Init Generates AGENTS.md From Template

**Area:** cli-init

## Problem

`scriptorium init` does not generate an AGENTS.md file. New projects have no
agent instructions until the user creates one manually.

## Requirements

- During init, check if `AGENTS.md` exists in the target repo root (on the
  default branch worktree, not the plan branch).
- If missing, copy `src/scriptorium/prompts/agents_example.md` to `AGENTS.md`.
- The template already exists as a staticRead resource in prompt_catalog.nim;
  use that or read the file directly.
- Commit the new AGENTS.md on the default branch (or leave it uncommitted for
  the user to review — follow what the spec says).
- Log which files were created.

## Files To Change

- `src/scriptorium/init.nim` — add AGENTS.md generation step.
- `tests/integration_cli.nim` — verify AGENTS.md is created when missing.

## Acceptance Criteria

- Running `scriptorium init` on a repo without AGENTS.md creates one from the template.
- Running `scriptorium init` on a repo that already has AGENTS.md skips this step.
- The generated file matches `agents_example.md` content.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0056-init-generates-agents-md

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Single-file change in init.nim to check for AGENTS.md existence and copy a template, plus a straightforward integration test addition — minimal logic complexity with one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0056-init-generates-agents-md/.scriptorium/logs/0056/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0056-init-generates-agents-md/.scriptorium/logs/0056/attempt-01.last_message.txt\n
### Agent Last Message
```text
The PR was successfully submitted — "Merge request enqueued." The work is complete.
```

### Agent Stdout Tail
```text
input_tokens":0},"output_tokens":1},"context_management":null},"parent_tool_use_id":null,"session_id":"4aefe7f5-478e-4d7e-b736-29b678bbd386","uuid":"3854991f-f68d-4714-8724-c87925953153"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":6364,"duration_api_ms":194362,"num_turns":2,"result":"The PR was successfully submitted — \"Merge request enqueued.\" The work is complete.","stop_reason":"end_turn","session_id":"4aefe7f5-478e-4d7e-b736-29b678bbd386","total_cost_usd":1.3344950000000004,"usage":{"input_tokens":4,"cache_creation_input_tokens":2322,"cache_read_input_tokens":85026,"output_tokens":156,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":2322},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":129,"outputTokens":7700,"cacheReadInputTokens":1190850,"cacheCreationInputTokens":87348,"webSearchRequests":0,"costUSD":1.3344950000000004,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"e273fb3a-3f03-4f15-862c-3ff2ed1be672"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 2m15s
