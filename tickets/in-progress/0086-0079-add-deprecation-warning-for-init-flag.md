# 0079 Add deprecation warning for --init flag

**Area:** cli-init

## Description

Per V11 §37, `scriptorium init [path]` is the canonical subcommand. The `--init` flag is kept as a deprecated alias. When `--init` is used, print a deprecation warning before running init:

```
Warning: --init is deprecated, use `scriptorium init` instead.
```

## Tasks

1. In `src/scriptorium.nim`, in the `--init` case branch (around line 179), add a stderr warning before calling `cmdInit`.
2. Update `tests/integration_cli.nim` test "--init flag works as alias for init subcommand" to also check for the deprecation warning in the output.
3. Run `make test` to confirm.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0086-0079-add-deprecation-warning-for-init-flag

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 10
- reasoning: Two-file change adding a stderr warning line and updating an existing test assertion, straightforward with no integration risk.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0086/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0086/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes:

- **`src/scriptorium.nim`**: Split the `"init", "--init"` case into separate branches. The `--init` branch now prints `Warning: --init is deprecated, use 'scriptorium init' instead.` to stderr before calling `cmdInit`.
- **`tests/integration_cli.nim`**: Added a check that the deprecation warning appears in the output when using `--init`.
```

### Agent Stdout Tail
```text
0325,"num_turns":18,"result":"Done. Changes:\n\n- **`src/scriptorium.nim`**: Split the `\"init\", \"--init\"` case into separate branches. The `--init` branch now prints `Warning: --init is deprecated, use 'scriptorium init' instead.` to stderr before calling `cmdInit`.\n- **`tests/integration_cli.nim`**: Added a check that the deprecation warning appears in the output when using `--init`.","stop_reason":"end_turn","session_id":"f43e4568-a39a-4964-9e3e-6dd75242e33e","total_cost_usd":0.30615699999999996,"usage":{"input_tokens":17,"cache_creation_input_tokens":20224,"cache_read_input_tokens":223044,"output_tokens":2726,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":20224},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":17,"outputTokens":2726,"cacheReadInputTokens":223044,"cacheCreationInputTokens":20224,"webSearchRequests":0,"costUSD":0.30615699999999996,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"1af1eb4b-1f44-4196-9843-64dbe553b1d0"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 31s

**Review Reasoning:** The diff is clean and correct. Let me verify the details:

1. **Ticket compliance**: The `--init` branch prints the exact required deprecation message to stderr before calling `cmdInit`. The integration test checks for the warning. Both tasks satisfied.

2. **Spec compliance**: V11 §37 says `--init` may be kept as a deprecated alias — this implements exactly that with a warning directing users to `scriptorium init`.

3. **Conventions**: No new procs, no import changes, no naming issues. The two-line duplication (`let path` + `cmdInit(path)`) across the `"init"` and `"--init"` branches is acceptable — it's clearer than extracting a helper for two lines.

4. **Code quality**: No dead code, no unused imports, no leftover artifacts. The change is minimal and focused.
Review approved. The change is minimal, correct, and matches the ticket requirements exactly.
