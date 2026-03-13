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
