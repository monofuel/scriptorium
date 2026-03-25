# 0104 Add audit CLI command entry point

**Area:** cli-init

## Problem

The spec (Section 1) requires the CLI to support `audit`, but `src/scriptorium.nim` has no case branch for it. The audit agent area owns the full implementation, but the CLI dispatch belongs to cli-init.

## Task

1. In `src/scriptorium.nim`, add a case branch for `"audit"` in the `case args[0]` block.
2. Create a `cmdAudit` proc that calls a `runAudit` proc from a new or existing module.
3. Create `src/scriptorium/audit_agent_cli.nim` with a `runAudit*(repoPath: string)` proc stub that prints an error and quits: `echo "scriptorium: audit command not yet implemented"; quit(1)`.
4. Add `"audit"` to the `Usage` help string (after `ask`).
5. Run `make test` to confirm compilation and existing tests pass.

## Files

- `src/scriptorium.nim`
- `src/scriptorium/audit_agent_cli.nim` (new)

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0112-0104-add-audit-cli-command-entry-point

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 10
- reasoning: Straightforward stub addition: add a case branch in the main CLI dispatcher, create a one-file stub module, and update a help string — all clearly specified with minimal logic.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0112/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0112/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes:

1. **`src/scriptorium/audit_agent_cli.nim`** (new) — stub `runAudit*` proc that prints "not yet implemented" and quits with exit code 1.
2. **`src/scriptorium.nim`** — imported `audit_agent_cli`, added `cmdAudit` proc, added `"audit"` case branch in the dispatcher, and added `audit` to the Usage help string after `ask`.

All existing tests pass.
```

### Agent Stdout Tail
```text
s":14,"result":"Done. Changes:\n\n1. **`src/scriptorium/audit_agent_cli.nim`** (new) — stub `runAudit*` proc that prints \"not yet implemented\" and quits with exit code 1.\n2. **`src/scriptorium.nim`** — imported `audit_agent_cli`, added `cmdAudit` proc, added `\"audit\"` case branch in the dispatcher, and added `audit` to the Usage help string after `ask`.\n\nAll existing tests pass.","stop_reason":"end_turn","session_id":"fa97a024-330c-40c4-9c59-24528171d474","total_cost_usd":0.29067000000000004,"usage":{"input_tokens":12,"cache_creation_input_tokens":25458,"cache_read_input_tokens":167545,"output_tokens":1909,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":25458},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":12,"outputTokens":1909,"cacheReadInputTokens":167545,"cacheCreationInputTokens":25458,"webSearchRequests":0,"costUSD":0.29067000000000004,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"cc1add67-de0b-49e1-afee-8f7716a04cef"}
```
