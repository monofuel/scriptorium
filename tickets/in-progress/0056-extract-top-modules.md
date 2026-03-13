# Extract Top-Level Modules From orchestrator.nim (Batch 3)

**Area:** orchestrator
**Depends:** 0055

## Problem

Final V7 §27 module split batch. Extract top-level modules that depend on the leaf and mid-level modules: `merge_queue.nim`, `coding_agent.nim`, `architect_agent.nim`, `manager_agent.nim`, `ticket_assignment.nim`, `mcp_server.nim`, and `interactive_sessions.nim`.

## Requirements

### mcp_server.nim
- Move MCP HTTP server setup: `setupMcpServer`, tool registration (`submit_pr`, `submit_review`), `runHttpServer`, `waitForServerReady`, `ServerThreadArgs`.

### ticket_assignment.nim
- Move ticket assignment procs: `assignOldestOpenTicket`, `assignOpenTickets`, parallel assignment logic.

### coding_agent.nim
- Move coding agent execution: `executeAssignedTicket`, agent thread management, `AgentThreadArgs`, stall detection and continuation procs.

### merge_queue.nim
- Move merge queue processing: `processMergeQueue`, `runReviewAgent`, merge/test/fast-forward logic, queue item creation and consumption.

### architect_agent.nim
- Move architect agent procs: `runArchitectAreas`, `syncAreasFromSpec`, `architectShouldRun`, spec hash marker logic.

### manager_agent.nim
- Move manager agent procs: `runManagerTickets`, `managerShouldRunForArea`, area hash marker logic.

### interactive_sessions.nim
- Move interactive session procs: `runInteractivePlanSession`, `runInteractiveAskSession`, `PlanTurn` type.

### Final state
- `orchestrator.nim` retains only the main loop (`runOrchestratorMainLoop`), signal handlers, `runOrchestratorLoop`, `runOrchestrator`, and `runOrchestratorForTicks` entry points.

## Acceptance Criteria

- All target modules exist under `src/scriptorium/`.
- `orchestrator.nim` contains only main loop and entry points.
- `make test` passes after each extraction commit.
- No functional changes.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0056-extract-top-modules

## Prediction
- predicted_difficulty: hard
- predicted_duration_minutes: 30
- reasoning: Extracting 7 top-level modules with cross-module dependencies is high volume; pattern is established from prior batches but dependency ordering and import wiring across this many interconnected modules creates integration risk, likely 2 attempts.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0056-extract-top-modules/.scriptorium/logs/0056/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0056-extract-top-modules/.scriptorium/logs/0056/attempt-01.last_message.txt\n
### Agent Last Message
```text
The work is complete. The `submit_pr` MCP call returned "Merge request enqueued." successfully. All 7 modules have been extracted, tests pass, and the merge request is queued.
```

### Agent Stdout Tail
```text
use_id":null,"session_id":"2056f153-6593-47a5-a5b4-90c4771333c5","uuid":"544b218c-e56b-4fa2-92c9-45fda6a7c36c"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":4113,"duration_api_ms":1119844,"num_turns":1,"result":"The work is complete. The `submit_pr` MCP call returned \"Merge request enqueued.\" successfully. All 7 modules have been extracted, tests pass, and the merge request is queued.","stop_reason":"end_turn","session_id":"2056f153-6593-47a5-a5b4-90c4771333c5","total_cost_usd":9.774428000000002,"usage":{"input_tokens":3,"cache_creation_input_tokens":4635,"cache_read_input_tokens":161527,"output_tokens":48,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":4635,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":111,"outputTokens":65422,"cacheReadInputTokens":12490071,"cacheCreationInputTokens":302926,"webSearchRequests":0,"costUSD":9.774428000000002,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"e4549a12-88a0-4df6-90f1-98a6a8014bc1"}
```
