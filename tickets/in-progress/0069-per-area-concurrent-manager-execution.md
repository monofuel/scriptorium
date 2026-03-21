# Per-Area Concurrent Manager Execution

**Area:** parallel-execution

**Depends:** 0068

## Problem

V13 §29 requires each eligible area to spawn an independent manager agent using the `manager_tickets.md` single-area prompt template, replacing the batched single-prompt model. Manager agents should generate ticket content in memory — only the orchestrator main thread writes to the plan worktree.

## Requirements

1. Create `proc buildManagerTicketsPrompt*(repoPath, planPath: string, areaId, areaRelPath, areaContent: string, nextId: int): string` in `prompt_builders.nim` using the existing `ManagerTicketsTemplate` from `prompt_catalog.nim`. The prompt should cover a single area.
2. Create `proc executeManagerForArea*(areaId, areaContent: string, repoPath, planPath: string, nextId: int, runner: AgentRunner): seq[string]` in `manager_agent.nim` that:
   - Builds the single-area prompt.
   - Runs the manager agent (using the `agents.manager` config for harness/model).
   - Parses generated ticket documents from agent output.
   - Returns ticket documents as a sequence of strings (in-memory, no filesystem writes).
3. Integrate with the shared agent pool from ticket 0068: manager agents use `startAgentAsync()` with `arManager` role, passing `executeManagerForArea` as the worker.
4. The orchestrator main thread handles manager completions from `checkCompletedAgents()`: acquires plan lock, calls a new `writeTicketsForArea()` proc to persist tickets, commits, releases lock.
5. Add `proc writeTicketsForArea*(planPath: string, areaId: string, ticketDocs: seq[string], nextId: int)` to `manager_agent.nim` that writes ticket files to `tickets/open/`.
6. `make test` must pass. Add unit tests for single-area prompt building and ticket document parsing.

## Notes

- The `manager_tickets.md` prompt template already exists in `src/scriptorium/prompts/`.
- Manager agents share the `maxAgents` slot pool with coding agents.
- Managers are prioritized over coders when slots are scarce (implemented in tick restructuring, ticket 0071).

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0069-per-area-concurrent-manager-execution

## Prediction
- predicted_difficulty: hard
- predicted_duration_minutes: 30
- reasoning: Cross-module changes spanning prompt_builders, manager_agent, agent_pool integration, and orchestrator wiring, plus new unit tests for prompt building and ticket parsing — high integration risk with concurrency primitives likely requiring 2+ attempts.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 137\n- Attempt: 5\n- Attempt Count: 5\n- Timeout: no-output\n- Log File: /workspace/.scriptorium/worktrees/tickets/0069-per-area-concurrent-manager-execution/.scriptorium/logs/0069/attempt-05.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0069-per-area-concurrent-manager-execution/.scriptorium/logs/0069/attempt-05.last_message.txt\n
### Agent Last Message
```text
There are pre-existing test failures (model resolution issues like `capturedModel == "claude-opus-4-6"`) that aren't related to my changes. Let me verify these failures exist on the base branch too.
```

### Agent Stdout Tail
```text
l_use_id":null,"session_id":"4c593b01-f610-49d0-a897-ee2f537f8fc2","uuid":"6406866b-04d8-4fb5-95d0-86ec7aef1ad9","timestamp":"2026-03-21T13:26:22.884Z","tool_use_result":{"retrieval_status":"timeout","task":{"task_id":"bqu1iwk71","task_type":"local_bash","status":"running","description":"Check if failures exist without my changes","output":"Saved working directory and index state WIP on scriptorium/ticket-0069: 0ef331f feat: extract agent_pool module with AgentRole enum and generic startAgentAsync\n","exitCode":null}}}
{"type":"assistant","message":{"model":"claude-opus-4-6","id":"msg_bdrk_01TRwJeNivnr3Xs1x84gExCb","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_bdrk_01AbkxtHRBE6DZyuxjrqa8SJ","name":"TaskOutput","input":{"task_id":"bqu1iwk71","block":true,"timeout":300000}}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"cache_creation_input_tokens":311,"cache_read_input_tokens":28530,"cache_creation":{"ephemeral_5m_input_tokens":311,"ephemeral_1h_input_tokens":0},"output_tokens":25},"context_management":null},"parent_tool_use_id":null,"session_id":"4c593b01-f610-49d0-a897-ee2f537f8fc2","uuid":"36416c52-729e-462c-af38-0cbba4992010"}
```
