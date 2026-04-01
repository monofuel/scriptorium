# 0091 — Wire per-role timeouts into agent callers

**Area:** harness-backends
**Priority:** medium
**Depends:** 0090

## Problem

Each agent caller currently uses either hardcoded constants or the global `cfg.timeouts` object for timeout values instead of reading from the per-role `agents.<role>` config. The spec requires per-role timeout configuration.

## Task

Update the following files to read timeouts from `AgentConfig` timeout fields:

### 1. `src/scriptorium/architect_agent.nim`
- `runPlanArchitectRequest` and `runDoArchitectRequest` currently use hardcoded `PlanNoOutputTimeoutMs` and `PlanHardTimeoutMs` constants.
- Change these to read from `agentCfg.noOutputTimeout` and `agentCfg.hardTimeout` (the `agentCfg: AgentConfig` parameter is already passed in).
- Keep the constants as fallback defaults in `config.nim` (ticket 0090 handles that).

### 2. `src/scriptorium/coding_agent.nim`
- `executeAssignedTicket` currently reads `cfg.timeouts.codingAgentNoOutputTimeoutMs`, `cfg.timeouts.codingAgentHardTimeoutMs`, `cfg.timeouts.codingAgentProgressTimeoutMs`.
- Change to read from `agentCfg.noOutputTimeout`, `agentCfg.hardTimeout`, `agentCfg.progressTimeout` where `agentCfg` comes from `cfg.agents.coding`.

### 3. `src/scriptorium/manager_agent.nim`
- `runManagerTicketGeneration` currently sets no timeout fields on the `AgentRunRequest`.
- Add `noOutputTimeoutMs: cfg.agents.manager.noOutputTimeout`, `hardTimeoutMs: cfg.agents.manager.hardTimeout`, `progressTimeoutMs: cfg.agents.manager.progressTimeout`.

### 4. `src/scriptorium/merge_queue.nim`
- The review agent request currently uses hardcoded `ReviewAgentNoOutputTimeoutMs` and `ReviewAgentHardTimeoutMs`.
- Change to read from `cfg.agents.reviewer.noOutputTimeout` and `cfg.agents.reviewer.hardTimeout`.

Ensure existing unit and integration tests still pass (`make test`).

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0102-0091-wire-per-role-timeouts-into-agent-callers

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Four files need mechanical substitution of hardcoded constants/global config reads with already-available AgentConfig fields — no new logic, no new types, and the parameter plumbing is already in place from ticket 0090.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0102/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0102/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. All four files updated to read timeouts from `AgentConfig` fields instead of hardcoded constants:

- **architect_agent.nim**: `runPlanArchitectRequest` and `runDoArchitectRequest` now use `agentCfg.noOutputTimeout` / `agentCfg.hardTimeout`
- **coding_agent.nim**: Already wired from ticket 0090 — no changes needed
- **manager_agent.nim**: `executeManagerForArea` now sets all three timeout fields from `cfg.agents.manager`
- **merge_queue.nim**: Review request now reads from `cfg.agents.reviewer` instead of `ReviewAgentNoOutputTimeoutMs` / `ReviewAgentHardTimeoutMs`
```

### Agent Stdout Tail
```text
uest` and `runDoArchitectRequest` now use `agentCfg.noOutputTimeout` / `agentCfg.hardTimeout`\n- **coding_agent.nim**: Already wired from ticket 0090 — no changes needed\n- **manager_agent.nim**: `executeManagerForArea` now sets all three timeout fields from `cfg.agents.manager`\n- **merge_queue.nim**: Review request now reads from `cfg.agents.reviewer` instead of `ReviewAgentNoOutputTimeoutMs` / `ReviewAgentHardTimeoutMs`","stop_reason":"end_turn","session_id":"0ccde468-1b37-405e-9d70-815bbbaf84d2","total_cost_usd":0.5191745,"usage":{"input_tokens":14,"cache_creation_input_tokens":38902,"cache_read_input_tokens":396234,"output_tokens":3114,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":38902,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":14,"outputTokens":3114,"cacheReadInputTokens":396234,"cacheCreationInputTokens":38902,"webSearchRequests":0,"costUSD":0.5191745,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"becac88c-8caa-4301-bde9-aa9d59b6e74a"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 32s

**Review Reasoning:** Let me verify the coding agent claim and inspect the changed files for correctness.
All four files check out:

1. **architect_agent.nim** — Correctly reads `agentCfg.noOutputTimeout` / `agentCfg.hardTimeout` instead of `PlanNoOutputTimeoutMs` / `PlanHardTimeoutMs`.
2. **coding_agent.nim** — Already wired from ticket 0090 (confirmed: lines 191-193 use `agentCfg.*` fields). No changes needed.
3. **manager_agent.nim** — Correctly adds all three timeout fields from `cfg.agents.manager`.
4. **merge_queue.nim** — Correctly reads from `cfg.agents.reviewer` instead of `ReviewAgent*` constants.

No convention violations, no spec contradictions, no dead code or unrelated changes.
Approved. The changes are a clean mechanical substitution — each caller now reads timeouts from the per-role `AgentConfig` fields as the spec requires, with no extraneous modifications.

## Merge Queue Success
- Summary: Wire per-role timeouts into agent callers: architect reads from agentCfg.noOutputTimeout/hardTimeout instead of PlanNoOutputTimeoutMs/PlanHardTimeoutMs constants, manager adds noOutputTimeoutMs/hardTimeoutMs/progressTimeoutMs from cfg.agents.manager, and reviewer reads from cfg.agents.reviewer instead of ReviewAgent* constants. Coding agent was already wired from ticket 0090.\n
### Quality Check Output
```text
strator_flow.nim]  1555 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
[tests/integration_orchestrator_flow.nim] /home/scriptorium/.cache/nim/integration_orchestrator_flow_d/@pjson.nim.c:2883:1: fatal error: error writing to /dev/shm/cctVQ3Ry.s: No space left on device
[tests/integration_orchestrator_flow.nim]  2883 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
[tests/integration_orchestrator_flow.nim] /home/scriptorium/.cache/nim/integration_orchestrator_flow_d/@pstrutils.nim.c:3537:1: fatal error: error writing to /dev/shm/cccV5s6y.s: No space left on device
[tests/integration_orchestrator_flow.nim]  3537 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
[tests/integration_orchestrator_flow.nim] /home/scriptorium/.cache/nim/integration_orchestrator_flow_d/@ptimes.nim.c:3801:1: fatal error: error writing to /dev/shm/cc46eXYy.s: No space left on device
[tests/integration_orchestrator_flow.nim]  3801 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
[tests/integration_orchestrator_flow.nim] /home/scriptorium/.cache/nim/integration_orchestrator_flow_d/@ptables.nim.c:8698:1: fatal error: error writing to /dev/shm/cc86kPkG.s: No space left on device
[tests/integration_orchestrator_flow.nim]  8698 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
[tests/integration_orchestrator_flow.nim] /home/scriptorium/.cache/nim/integration_orchestrator_flow_d/@psystem.nim.c:14454:1: fatal error: error writing to /dev/shm/ccr7FGOo.s: No space left on device
[tests/integration_orchestrator_flow.nim] 14454 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
```

## Metrics
- wall_time_seconds: 400
- coding_wall_seconds: 76
- test_wall_seconds: 17
- attempt_count: 1
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 277742

## Post-Analysis
- actual_difficulty: easy
- prediction_accuracy: accurate
- brief_summary: Predicted easy, actual was easy with 1 attempt(s) in 6m40s.
