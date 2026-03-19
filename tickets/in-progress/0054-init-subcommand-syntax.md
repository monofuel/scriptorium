# Change --init Flag To init Subcommand

**Area:** cli-init

## Problem

The current CLI uses `scriptorium --init [path]` flag syntax. The spec requires
`scriptorium init [path]` subcommand syntax instead.

## Requirements

- Add `init` as a subcommand in the CLI argument parser in `src/scriptorium.nim`.
- `scriptorium init` with no path argument defaults to the current directory.
- `scriptorium init <path>` initializes the given path.
- Remove or deprecate the `--init` flag.
- Update `--help` output to show `init` as a subcommand alongside `run`, `status`,
  `plan`, `ask`, and `worktrees`.
- Update all references to `--init` in code comments and log messages.

## Files To Change

- `src/scriptorium.nim` — CLI argument parsing.
- `src/scriptorium/init.nim` — if any flag-specific logic exists.
- `tests/integration_cli.nim` — update test to use `init` subcommand.

## Acceptance Criteria

- `scriptorium init` works as a subcommand.
- `scriptorium --init` no longer works (or prints a deprecation message).
- Existing tests pass with the new syntax.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0054-init-subcommand-syntax

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Straightforward CLI refactor in a single main file changing flag-based parsing to subcommand parsing, with minor test updates — low integration risk, one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0054-init-subcommand-syntax/.scriptorium/logs/0054/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0054-init-subcommand-syntax/.scriptorium/logs/0054/attempt-01.last_message.txt\n
### Agent Last Message
```text
`submit_pr` succeeded — the orchestrator responded with "Merge request enqueued." The ticket is now in the merge queue.
```

### Agent Stdout Tail
```text
,"context_management":null},"parent_tool_use_id":null,"session_id":"ea4ccba5-03bd-44d3-9523-1f6657ffe587","uuid":"93f52920-4d97-4c73-bd56-c5ba91cf6c4e"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":7362,"duration_api_ms":188285,"num_turns":2,"result":"`submit_pr` succeeded — the orchestrator responded with \"Merge request enqueued.\" The ticket is now in the merge queue.","stop_reason":"end_turn","session_id":"ea4ccba5-03bd-44d3-9523-1f6657ffe587","total_cost_usd":1.2411565000000002,"usage":{"input_tokens":4,"cache_creation_input_tokens":533,"cache_read_input_tokens":108137,"output_tokens":164,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":533},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":197,"outputTokens":5916,"cacheReadInputTokens":1504168,"cacheCreationInputTokens":54430,"webSearchRequests":0,"costUSD":1.2411565000000002,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"b52664a3-0c37-4f27-b9fa-9aa78ba12182"}
```
