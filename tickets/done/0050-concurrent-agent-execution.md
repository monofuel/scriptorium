# Concurrent Agent Execution With Isolated Worktrees

**Area:** parallel-execution

## Problem

With the non-blocking tick (ticket 0049) providing the framework, the actual concurrent agent execution needs to be wired up: multiple coding agent processes running in parallel, each in its own worktree, with independent lifecycle management.

## Requirements

1. Each agent slot runs its coding agent process in a separate thread or as a separate subprocess, fully isolated in its own worktree.
2. Thread-safe shared state for MCP tool handlers (`submit_pr`, `submit_review`):
   - The current `activeWorktreePathBuffer`/`activeTicketIdBuffer` pattern supports only one active agent. Refactor to support per-ticket state so MCP handlers can identify which ticket is calling.
   - Option: use ticket ID from MCP request context, or maintain a concurrent map of active agents.
3. Stall detection (no-output timeout, hard timeout) applies independently per running agent.
4. Continuation prompts on stall apply per-agent — one agent stalling does not affect others.
5. Per-ticket metrics tables (`ticketStartTimes`, `ticketCodingWalls`, etc.) are already keyed by ticket ID and should work concurrently, but verify thread safety.
6. Add integration test verifying two agents can run concurrently in separate worktrees without interfering.

## Dependencies

- Ticket 0049 (non-blocking tick with agent tracking)

## Acceptance Criteria

- `make test` passes.
- Two coding agents can run simultaneously when `maxAgents >= 2`.
- MCP `submit_pr` correctly identifies the calling agent's ticket.
- Stall detection works independently per agent.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0050-concurrent-agent-execution

## Prediction
- predicted_difficulty: hard
- predicted_duration_minutes: 90
- reasoning: Requires refactoring shared mutable state (activeWorktreePathBuffer/activeTicketIdBuffer) to support concurrent access, wiring up multi-threaded/subprocess agent execution with independent lifecycle management, ensuring thread safety across MCP handlers and metrics tables, and adding integration tests for parallel worktree isolation.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0050-concurrent-agent-execution/.scriptorium/logs/0050/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0050-concurrent-agent-execution/.scriptorium/logs/0050/attempt-01.last_message.txt\n
### Agent Last Message
```text
All work is complete. Here's a summary of what was done:

**Changes made:**

1. **Thread-safe plan worktree access** (`orchestrator.nim`): Added `planWorktreeLock` (in-process Lock) to serialize `withPlanWorktree` and `withLockedPlanWorktree` calls across threads, preventing git lock contention when multiple agents access the plan branch concurrently.

2. **Configurable runner for parallel agents** (`orchestrator.nim`): Added `agentRunnerOverride` global that `agentWorkerThread` consults, allowing `runOrchestratorMainLoop` to propagate a custom runner to background agent threads. This enables both testing and future runner customization.

3. **Ticket ID in coding agent prompt** (`coding_agent.md`, `orchestrator.nim`): Added `{{TICKET_ID}}` placeholder to the prompt template so agents include `ticket_id` when calling `submit_pr`, ensuring correct identification in parallel mode.

4. **Three unit tests** (`test_scriptorium.nim`):
   - Two agents run concurrently in separate worktrees without interfering
   - `submit_pr` correctly identifies the calling agent's ticket via `ticket_id`
   - Stall detection works independently per agent (one stalls, one submits)
```

### Agent Stdout Tail
```text
es without interfering\n   - `submit_pr` correctly identifies the calling agent's ticket via `ticket_id`\n   - Stall detection works independently per agent (one stalls, one submits)","stop_reason":"end_turn","session_id":"42ba0aac-07dc-45a8-82bf-d6bf106dca34","total_cost_usd":4.4030796999999975,"usage":{"input_tokens":241,"cache_creation_input_tokens":105291,"cache_read_input_tokens":5639895,"output_tokens":26905,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":105291,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":241,"outputTokens":26905,"cacheReadInputTokens":5639895,"cacheCreationInputTokens":105291,"webSearchRequests":0,"costUSD":4.151846249999998,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":38,"outputTokens":8854,"cacheReadInputTokens":969017,"cacheCreationInputTokens":88019,"webSearchRequests":0,"costUSD":0.25123345,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"75a46d4d-8308-480d-a1cb-366fab211863"}
```
