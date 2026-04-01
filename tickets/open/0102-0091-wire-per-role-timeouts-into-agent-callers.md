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
