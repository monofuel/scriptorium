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

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0112/attempt-02.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0112/attempt-02.last_message.txt\n
### Agent Last Message
```text
Submitted. The changes were already complete from the previous attempt — audit CLI entry point with case branch, `cmdAudit` proc, stub module, and help string update.
```

### Agent Stdout Tail
```text
,"parent_tool_use_id":null,"session_id":"75e1deb1-2819-4787-a268-6be5b1d6acd4","uuid":"07c356da-a16b-4bc0-b3d7-eda5f6fa39b4"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":21942,"duration_api_ms":21810,"num_turns":7,"result":"Submitted. The changes were already complete from the previous attempt — audit CLI entry point with case branch, `cmdAudit` proc, stub module, and help string update.","stop_reason":"end_turn","session_id":"75e1deb1-2819-4787-a268-6be5b1d6acd4","total_cost_usd":0.12699325,"usage":{"input_tokens":9,"cache_creation_input_tokens":13797,"cache_read_input_tokens":45684,"output_tokens":715,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":13797},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":9,"outputTokens":715,"cacheReadInputTokens":45684,"cacheCreationInputTokens":13797,"webSearchRequests":0,"costUSD":0.12699325,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"efffdcfd-8cc8-4555-9310-80dddceeade8"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 23s

**Review Reasoning:** Let me review the changes against the ticket requirements and project conventions.
The implementation looks correct. Let me verify against all requirements:

**Ticket requirements:**
1. Case branch for `"audit"` in dispatcher — present at line 110-111.
2. `cmdAudit` proc calling `runAudit` — present at lines 79-81.
3. `src/scriptorium/audit_agent_cli.nim` with `runAudit*(repoPath: string)` stub that prints error and quits — present and correct.
4. `"audit"` added to Usage help string after `ask` — present at line 16.
5. Tests pass — agent confirmed.

**Convention checks:**
- Import style: single block, bracket syntax, std/ first then local — correct.
- Doc comments on every proc with `##`, complete sentences with punctuation — correct.
- No forward declarations — correct.
- Constants PascalCase, variables camelCase — correct.
- No try/catch, no boolean error returns — correct.

**Spec compliance:**
- Spec §1 lists `audit` as a required CLI command — implemented.
- Spec §19 says `scriptorium audit` runs the audit agent on demand — the stub is appropriate for this cli-init area ticket; full implementation belongs to the audit agent area.

**Code quality:**
- No dead code, no unused imports, no leftover artifacts, no unrelated changes.

Everything looks clean.
Approved. The implementation cleanly satisfies all five ticket requirements, follows project conventions (import style, doc comments, naming, error handling), and aligns with the spec. The stub is appropriately scoped to the cli-init area.

## Merge Queue Success
- Summary: Added audit CLI command entry point: case branch for "audit" in the main dispatcher, cmdAudit proc, stub runAudit proc in new src/scriptorium/audit_agent_cli.nim module, and "audit" in the Usage help string.\n
### Quality Check Output
```text
] journal: began transition — complete 0001
[tests/integration_orchestrator_queue.nim] [2026-03-25T05:54:04Z] [INFO] journal: executed steps — complete 0001
[tests/integration_orchestrator_queue.nim] [2026-03-25T05:54:04Z] [INFO] journal: transition complete
[tests/integration_orchestrator_queue.nim] [2026-03-25T05:54:04Z] [INFO] merge queue: item processed
[tests/integration_orchestrator_queue.nim] [2026-03-25T05:54:04Z] [INFO] tick 0 summary: architect=updated manager=no-op coding=1/4 agents merge=processing agents=1/4 open=0 in-progress=0 done=1 stuck=0 loop=0
[tests/integration_orchestrator_queue.nim] [2026-03-25T05:54:04Z] [INFO] shutdown: waiting for 1 running agent(s)
[tests/integration_orchestrator_queue.nim] [2026-03-25T05:57:02Z] [INFO] session summary: uptime=4m7s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[tests/integration_orchestrator_queue.nim] [2026-03-25T05:57:02Z] [INFO] session summary: avg_ticket_wall=23s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
[tests/integration_orchestrator_queue.nim]   [OK] IT-10 global halt while red resumes after master health is restored
[tests/integration_orchestrator_queue.nim] [2026-03-25T05:57:02Z] [INFO] orchestrator PID guard acquired (PID 102308)
[tests/integration_orchestrator_queue.nim] [2026-03-25T05:57:02Z] [INFO] recovery: clean startup, no recovery needed
[tests/integration_orchestrator_queue.nim] [2026-03-25T05:57:02Z] [WARN] master is unhealthy — skipping tick
[tests/integration_orchestrator_queue.nim] [2026-03-25T05:57:02Z] [INFO] session summary: uptime=0s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[tests/integration_orchestrator_queue.nim] [2026-03-25T05:57:02Z] [INFO] session summary: avg_ticket_wall=23s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
[tests/integration_orchestrator_queue.nim]   [OK] IT-11 integration-test failure on master blocks assignment of open tickets
```

## Metrics
- wall_time_seconds: 748
- coding_wall_seconds: 74
- test_wall_seconds: 285
- attempt_count: 2
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 120322

## Post-Analysis
- actual_difficulty: hard
- prediction_accuracy: underestimated
- brief_summary: Predicted easy, actual was hard with 2 attempt(s) in 12m28s.
