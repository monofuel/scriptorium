# Retire Batched Manager Path

**Area:** parallel-execution

**Depends:** 0069

## Problem

V13 §32 requires removing the batched manager execution model now that per-area concurrent managers are implemented.

## Requirements

1. Remove `proc runManagerTickets*()` from `manager_agent.nim`.
2. Remove `proc syncTicketsFromAreas*()` from `manager_agent.nim` (if it exists).
3. Remove `ManagerTicketsBatchTemplate` export from `prompt_catalog.nim`.
4. Remove `proc buildManagerTicketsBatchPrompt*()` from `prompt_builders.nim`.
5. Delete the `src/scriptorium/prompts/manager_tickets_batch.md` prompt template file.
6. Update `orchestrator.nim` to remove calls to the batched manager path (the `runManagerTickets` call in the tick loop).
7. Update or remove unit tests that reference removed functions and templates.
8. `make test` must pass after all removals.

## Notes

- The production manager path after this ticket is the per-area concurrent model from ticket 0069.
- The single-area `manager_tickets.md` template and `ManagerTicketsTemplate` must be preserved.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0070-retire-batched-manager-path

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Straightforward deletion of well-enumerated functions, a template file, and their references across ~5 files with no new logic to write — just removals and test cleanup, one attempt expected.

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Straightforward deletion of well-enumerated functions, a template file, and their references across ~5 files with no new logic to write — just removals and test cleanup, one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0070-retire-batched-manager-path/.scriptorium/logs/0070/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0070-retire-batched-manager-path/.scriptorium/logs/0070/attempt-01.last_message.txt\n
### Agent Last Message
```text
Submitted. Here's a summary of the changes:

**Removed:**
- `runManagerTickets*()` and `syncTicketsFromAreas*()` from `manager_agent.nim`
- `ManagerTicketsBatchTemplate` from `prompt_catalog.nim`
- `buildManagerTicketsBatchPrompt*()` from `prompt_builders.nim`
- `src/scriptorium/prompts/manager_tickets_batch.md` template file
- 8 related unit tests

**Updated:**
- **orchestrator.nim**: Replaced batched `runManagerTickets` call with per-area execution — serial mode (`maxAgents<=1`) uses `executeManagerForArea` synchronously, parallel mode launches `startManagerAgentAsync` background threads
- **managerAgentWorkerThread**: Now creates its own plan worktree via `withPlanWorktree` instead of relying on a caller-provided (potentially stale) path
- Fixed a latent bug in `executeManagerForArea`'s fallback path where `listMarkdownFiles` returned absolute paths but was incorrectly prepended with `planPath`
- Updated 2 orchestrator tests to use `maxAgents=1` for single-tick determinism
- Updated the e2e happy path test to write tickets directly instead of via the removed `syncTicketsFromAreas`
```

### Agent Stdout Tail
```text
rovided (potentially stale) path\n- Fixed a latent bug in `executeManagerForArea`'s fallback path where `listMarkdownFiles` returned absolute paths but was incorrectly prepended with `planPath`\n- Updated 2 orchestrator tests to use `maxAgents=1` for single-tick determinism\n- Updated the e2e happy path test to write tickets directly instead of via the removed `syncTicketsFromAreas`","stop_reason":"end_turn","session_id":"8ba740a6-d5a4-47f2-bfbe-e52d937ca4e0","total_cost_usd":5.097461249999999,"usage":{"input_tokens":5292,"cache_creation_input_tokens":103101,"cache_read_input_tokens":7093990,"output_tokens":35185,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":103101},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":5292,"outputTokens":35185,"cacheReadInputTokens":7093990,"cacheCreationInputTokens":103101,"webSearchRequests":0,"costUSD":5.097461249999999,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"33ec47b2-7dde-4b37-b6d2-1048c084bbe9"}
```

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Straightforward deletion of well-enumerated functions, a template file, and their references across ~5 files with no new logic to write — just removals and test cleanup, one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0070-retire-batched-manager-path/.scriptorium/logs/0070/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0070-retire-batched-manager-path/.scriptorium/logs/0070/attempt-01.last_message.txt\n
### Agent Last Message
```text
Submitted. Summary of changes:

**Removed:**
- `runManagerTickets*()` and `syncTicketsFromAreas*()` from `manager_agent.nim`
- `ManagerTicketsBatchTemplate` from `prompt_catalog.nim`
- `buildManagerTicketsBatchPrompt*()` from `prompt_builders.nim`
- `ManagerTicketGenerator` type from `shared_state.nim`
- `src/scriptorium/prompts/manager_tickets_batch.md` template file
- 9 tests referencing removed functions

**Updated:**
- **orchestrator.nim**: Replaced batched `runManagerTickets` call with per-area execution — serial mode (`maxAgents<=1`) uses `executeManagerForArea` synchronously, parallel mode launches `startManagerAgentAsync` background threads
- 2 orchestrator tests updated to use `maxAgents=1` after `writeOrchestratorEndpointConfig` for deterministic serial execution
- e2e happy path test writes tickets directly instead of via removed `syncTicketsFromAreas`
```

### Agent Stdout Tail
```text
per-area execution — serial mode (`maxAgents<=1`) uses `executeManagerForArea` synchronously, parallel mode launches `startManagerAgentAsync` background threads\n- 2 orchestrator tests updated to use `maxAgents=1` after `writeOrchestratorEndpointConfig` for deterministic serial execution\n- e2e happy path test writes tickets directly instead of via removed `syncTicketsFromAreas`","stop_reason":"end_turn","session_id":"f857236f-bbb0-4d80-b92f-c86055dd7ff1","total_cost_usd":5.117739750000001,"usage":{"input_tokens":11371,"cache_creation_input_tokens":108475,"cache_read_input_tokens":7119882,"output_tokens":32919,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":108475},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":11371,"outputTokens":32919,"cacheReadInputTokens":7119882,"cacheCreationInputTokens":108475,"webSearchRequests":0,"costUSD":5.117739750000001,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"94941ad3-3dfe-42ea-9b55-72da819fb4ca"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 33s

## Merge Queue Failure
- Summary: Retired batched manager path: removed runManagerTickets, syncTicketsFromAreas, ManagerTicketsBatchTemplate, buildManagerTicketsBatchPrompt, ManagerTicketGenerator type, and manager_tickets_batch.md template. Replaced orchestrator tick loop manager call with per-area execution (serial mode uses executeManagerForArea synchronously, parallel mode launches startManagerAgentAsync). Removed 9 obsolete tests and updated 2 orchestrator tests to use maxAgents=1 for deterministic serial execution.\n- Failed gate: make integration-test\n
### Merge Output
```text
Already up to date.
```

### Quality Check Output
```text
TS.md
  [OK] run exits with error when plan branch is missing
  [OK] run exits with error when AGENTS.md is missing
  [OK] run exits with error when Makefile is missing
  [OK] run exits with error when Makefile lacks test target
  [OK] syncAgentsMd restores modified AGENTS.md to template
  [OK] syncAgentsMd is a no-op when AGENTS.md matches template
  [OK] syncAgentsMd respects syncAgentsMd false in config
--- tests/integration_codex_harness.nim ---

[Suite] integration codex harness
/workspace/.scriptorium/worktrees/tickets/0070-retire-batched-manager-path/tests/integration_codex_harness.nim(75) integration_codex_harness
/usr/lib/nim/lib/std/assertions.nim(41) failedAssertImpl
/usr/lib/nim/lib/std/assertions.nim(36) raiseAssert
/usr/lib/nim/lib/system/fatal.nim(53) sysFatal

    Unhandled exception: /workspace/.scriptorium/worktrees/tickets/0070-retire-batched-manager-path/tests/integration_codex_harness.nim(75, 7) `runResult.exitCode == 0` codex exec failed with non-zero exit code.
Model: gpt-5.1-codex-mini
Command: codex -c developer_instructions="" -c model_reasoning_effort="high" exec --json --output-last-message /tmp/scriptorium_integration_codex_evqTKAmv/logs/integration-smoke/attempt-01.last_message.txt --cd /tmp/scriptorium_integration_codex_evqTKAmv/worktree --model gpt-5.1-codex-mini --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check -
Stdout:
{"type":"thread.started","thread_id":"019d1422-5804-7ae2-854a-c5657dcfa2d1"}
{"type":"turn.started"}
 [AssertionDefect]
  [FAILED] real codex exec one-shot smoke test
[2026-03-22T06:01:43Z] [INFO] MCP server ready on 127.0.0.1:22677
[2026-03-22T06:01:46Z] [INFO] ticket unknown: submit_pr accepted (quality checks run in merge queue)
  [OK] real codex MCP tool call against live server
Error: execution of an external program failed: '/home/scriptorium/.cache/nim/integration_codex_harness_d/integration_codex_harness_8D9090D3B9F187F57442B58C68EB64F56974C59A'
make: *** [Makefile:35: integration-test] Error 1
```

## Metrics
- wall_time_seconds: 1758
- coding_wall_seconds: 1583
- test_wall_seconds: 0
- attempt_count: 1
- outcome: reopened
- failure_reason: test_failure
- model: claude-opus-4-6
- stdout_bytes: 2886534

## Post-Analysis
- actual_difficulty: hard
- prediction_accuracy: underestimated
- brief_summary: Predicted easy, actual was hard with 1 attempt(s) in 29m18s.

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: While the removals are well-enumerated, the post-mortem shows non-trivial orchestrator integration work (replacing batched call with per-area serial/parallel paths, fixing latent bugs, updating multiple test files) — more than simple deletions, but completed in one attempt.
