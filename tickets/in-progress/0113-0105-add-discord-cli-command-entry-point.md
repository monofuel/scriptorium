# 0105 Add discord CLI command entry point

**Area:** cli-init

## Problem

The spec (Section 1) requires the CLI to support `discord`, but `src/scriptorium.nim` has no case branch for it. The discord area owns the full bot implementation, but the CLI dispatch belongs to cli-init.

## Task

1. In `src/scriptorium.nim`, add a case branch for `"discord"` in the `case args[0]` block.
2. Create a `cmdDiscord` proc that calls a `runDiscord` proc from a new module.
3. Create `src/scriptorium/discord_cli.nim` with a `runDiscord*(repoPath: string)` proc stub that prints an error and quits: `echo "scriptorium: discord command not yet implemented"; quit(1)`.
4. Add `"discord"` to the `Usage` help string (after `audit`).
5. Run `make test` to confirm compilation and existing tests pass.

## Files

- `src/scriptorium.nim`
- `src/scriptorium/discord_cli.nim` (new)

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0113-0105-add-discord-cli-command-entry-point

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 10
- reasoning: Boilerplate CLI dispatch addition across two files with a stub proc, mirroring the existing audit command pattern, one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0113/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0113/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes:
- **`src/scriptorium.nim`**: Added `discord_cli` import, `"discord"` to Usage help, `cmdDiscord` proc, and `"discord"` case branch
- **`src/scriptorium/discord_cli.nim`** (new): Stub `runDiscord` proc that prints not-yet-implemented and exits with code 1
```

### Agent Stdout Tail
```text
4186416f503"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":60823,"duration_api_ms":56076,"num_turns":17,"result":"Done. Changes:\n- **`src/scriptorium.nim`**: Added `discord_cli` import, `\"discord\"` to Usage help, `cmdDiscord` proc, and `\"discord\"` case branch\n- **`src/scriptorium/discord_cli.nim`** (new): Stub `runDiscord` proc that prints not-yet-implemented and exits with code 1","stop_reason":"end_turn","session_id":"0b393391-e8dc-4937-980b-1a6325d0f541","total_cost_usd":0.3437495,"usage":{"input_tokens":14,"cache_creation_input_tokens":28868,"cache_read_input_tokens":216859,"output_tokens":2193,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":28868},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":14,"outputTokens":2193,"cacheReadInputTokens":216859,"cacheCreationInputTokens":28868,"webSearchRequests":0,"costUSD":0.3437495,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"d9c3cd07-5028-4c97-82aa-a2ceea5d86c9"}
```
