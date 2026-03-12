# Tick Summary Line

**Area:** observability

## Description

Add a single INFO-level summary line at the end of each orchestrator tick capturing full system state.

## Current State

Individual component timings are logged at DEBUG level during the tick loop (architect, manager, coding agent, merge queue), but there is no consolidated INFO-level summary line per tick. Ticket counts (open/in-progress/done) are computed in `readOrchestratorStatus()` but not logged per tick.

## Requirements

- At the end of each tick in the main orchestrator loop, emit exactly one INFO-level log line.
- Required fields:
  - `architect`: `no-op`, `updated`, or `skipped`.
  - `manager`: `no-op`, `updated`, or `skipped`.
  - `coding`: ticket ID + status (`running`, `stalled`, `submitted`, `failed`) + wall time, or `idle`.
  - `merge`: `idle`, `processing`, or ticket ID being merged.
  - `open` / `in-progress` / `done`: current ticket counts.
- Format example: `tick 42 summary: architect=no-op manager=no-op coding=0031(running, 3m12s) merge=idle open=2 in-progress=1 done=14`
- Wall times must be human-readable (e.g., `3m12s`).
- Every tick produces exactly one summary line.

## Implementation Notes

- Add a helper proc to format durations as human-readable strings (e.g., seconds to `3m12s`).
- Gather component statuses from existing tick loop variables (`architectChanged`, `managerChanged`, agent result, merge queue state).
- Count ticket files in open/in-progress/done directories using existing `listMarkdownFiles()`.
- Insert the summary `logInfo()` call at the end of the tick loop body in `orchestrator.nim`.

## Spec References

- Section 13: Tick Summary Line (V3).

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0033-tick-summary-line

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0033-tick-summary-line/.scriptorium/logs/0033/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0033-tick-summary-line/.scriptorium/logs/0033/attempt-01.last_message.txt\n
### Agent Last Message
```text
Successfully submitted. The changes:

1. **`src/scriptorium/agent_runner.nim`**: Added `ticketId` and `submitted` fields to `AgentRunResult` to carry ticket context and submission state back to the caller.

2. **`src/scriptorium/orchestrator.nim`**: 
   - Added `formatDuration*` proc to convert seconds to human-readable strings (e.g., `3m12s`)
   - Set `result.ticketId` and `result.submitted` in `executeOldestOpenTicket`/`executeAssignedTicket`
   - Added tick summary logic tracking `architectStatus`, `managerStatus`, `codingStatus`, `mergeStatus` throughout the tick loop
   - Emits one INFO-level summary line at end of each tick: `tick 42 summary: architect=no-op manager=no-op coding=0031(submitted, 3m12s) merge=idle open=2 in-progress=1 done=14`

3. **`tests/test_scriptorium.nim`**: Added `formatDuration` test suite covering seconds-only and minutes+seconds cases.
```

### Agent Stdout Tail
```text
gic tracking `architectStatus`, `managerStatus`, `codingStatus`, `mergeStatus` throughout the tick loop\n   - Emits one INFO-level summary line at end of each tick: `tick 42 summary: architect=no-op manager=no-op coding=0031(submitted, 3m12s) merge=idle open=2 in-progress=1 done=14`\n\n3. **`tests/test_scriptorium.nim`**: Added `formatDuration` test suite covering seconds-only and minutes+seconds cases.","stop_reason":"end_turn","session_id":"890ac008-4008-4c83-8025-385307095ed7","total_cost_usd":2.0932939999999998,"usage":{"input_tokens":69,"cache_creation_input_tokens":49094,"cache_read_input_tokens":2722923,"output_tokens":16986,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":49094,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":69,"outputTokens":16986,"cacheReadInputTokens":2722923,"cacheCreationInputTokens":49094,"webSearchRequests":0,"costUSD":2.0932939999999998,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"cc73010d-1c8d-462b-82f2-47475b0e13d2"}
```

## Merge Queue Success
- Summary: Add tick summary INFO line at end of each orchestrator tick with architect/manager/coding/merge statuses and open/in-progress/done ticket counts. Includes formatDuration helper and ticketId/submitted fields on AgentRunResult.\n
### Quality Check Output
```text
ium/orchestrator.nim(2204) runHttpServer
/home/scriptorium/.nimby/pkgs/MCPort/src/mcport/mcp_server_http.nim(241) serve
/home/scriptorium/.nimby/pkgs/mummy/src/mummy.nim(1445) serve
/home/scriptorium/.nimby/pkgs/mummy/src/mummy.nim(1247) loopForever
/home/scriptorium/.nimby/pkgs/mummy/src/mummy.nim(1125) destroy
/usr/lib/nim/lib/system/alloc.nim(1140) dealloc
/usr/lib/nim/lib/system/alloc.nim(1027) rawDealloc
/usr/lib/nim/lib/system/alloc.nim(790) addToSharedFreeList
SIGSEGV: Illegal storage access. (Attempt to read from nil?)
  [OK] IT-LIVE-04 live daemon does not enqueue when submit_pr is missing
--- tests/integration_orchestrator_queue.nim ---

[Suite] integration orchestrator merge queue
  [OK] IT-02 queue success moves ticket to done and merges ticket commit to master
  [OK] IT-03 queue failure reopens ticket and appends failure note
  [OK] IT-03b queue failure when integration-test fails reopens ticket
  [OK] IT-04 single-flight queue processing keeps second item pending
  [OK] IT-05 merge conflict during merge master into ticket reopens ticket
  [OK] IT-08 recovery after partial queue transition converges without duplicate moves
[2026-03-12T22:14:52Z] [WARN] master is unhealthy — skipping tick
  [OK] IT-09 red master blocks assignment of open tickets
[2026-03-12T22:15:22Z] [WARN] master is unhealthy — skipping tick
[2026-03-12T22:15:52Z] [INFO] architect: generating areas from spec
[2026-03-12T22:15:53Z] [INFO] architect: areas updated
[2026-03-12T22:15:53Z] [INFO] manager: generating tickets
[2026-03-12T22:15:53Z] [INFO] merge queue: processing
[2026-03-12T22:15:53Z] [INFO] merge queue: item processed
[2026-03-12T22:15:53Z] [INFO] tick 0 summary: architect=updated manager=no-op coding=idle merge=processing open=0 in-progress=0 done=1
  [OK] IT-10 global halt while red resumes after master health is restored
[2026-03-12T22:15:53Z] [WARN] master is unhealthy — skipping tick
  [OK] IT-11 integration-test failure on master blocks assignment of open tickets
```
