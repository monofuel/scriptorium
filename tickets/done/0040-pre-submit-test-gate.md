# Pre-Submit Test Gate In submit_pr MCP Tool

**Area:** agent-execution

## Problem

The `submit_pr` MCP tool handler in `orchestrator.nim` (line ~2566) unconditionally records the submit summary and returns "Merge request enqueued." without running any tests. The V4 spec (§20) requires `submit_pr` to run `make test` in the agent's worktree before accepting the submission.

## Current State

The handler is:
```nim
let submitPrHandler: ToolHandler = proc(arguments: JsonNode): JsonNode {.gcsafe.} =
  let summary = arguments["summary"].getStr()
  recordSubmitPrSummary(summary)
  %*"Merge request enqueued."
```

No tests are run. The merge queue later runs `make test` and `make integration-test`, but by then the coding agent has already exited.

## Requirements

- The `submit_pr` MCP tool handler must run `make test` in the coding agent's worktree before accepting the submission.
- The handler needs access to the current ticket's worktree path. This may require storing the active worktree path in a shared variable (similar to `submitPrSummaryBuffer`) or passing it through the handler closure.
- If `make test` fails:
  - Return an error JSON response to the agent with test failure output (truncated if long).
  - Direct the agent to fix failing tests and call `submit_pr` again.
  - Do NOT call `recordSubmitPrSummary()` — the merge request must NOT be enqueued.
- If `make test` passes:
  - Call `recordSubmitPrSummary()` and return success response as before.
- Log: `ticket <id>: submit_pr pre-check: <PASS|FAIL> (exit=<code>, wall=<duration>)`.
- The handler blocks while tests run — this is expected and counts against the agent's hard timeout.
- Only `make test` is run, not `make integration-test` (integration tests remain a merge queue concern).

## Implementation Notes

- Add a thread-safe shared variable for the active ticket worktree path (set when a ticket is assigned, cleared after execution).
- Add a thread-safe shared variable for the active ticket ID (for logging).
- Use `runQualityTarget("test", worktreePath)` or equivalent to run `make test`.
- Truncate test output in error responses to avoid overwhelming the agent (e.g., last 2000 chars).
- Update existing tests that verify `submit_pr` behavior.

## Acceptance Criteria

- `submit_pr` runs `make test` before enqueuing.
- Failing tests return error to agent without enqueuing.
- Passing tests enqueue normally.
- Pre-check logged with ticket ID, pass/fail, exit code, and wall time.
- Unit tests cover both pass and fail paths.

## Spec References

- Section 20: Pre-Submit Test Gate (V4).

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0040-pre-submit-test-gate

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 35
- reasoning: Requires adding shared state variables, modifying an existing handler with test execution and error handling logic, and updating unit tests, but the pattern is well-established in the codebase and the requirements are clearly specified.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0040-pre-submit-test-gate/.scriptorium/logs/0040/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0040-pre-submit-test-gate/.scriptorium/logs/0040/attempt-01.last_message.txt\n
### Agent Last Message
```text


**Changes in `src/scriptorium/orchestrator.nim`:**
- Added constants `SubmitPrTestOutputMaxChars` (2000), `ActiveWorktreePathMaxBytes` (1024), `ActiveTicketIdMaxBytes` (256)
- Added thread-safe shared variables `activeWorktreePathBuffer`/`activeTicketIdBuffer` (same pattern as `submitPrSummaryBuffer`)
- Added `setActiveTicketWorktree`, `clearActiveTicketWorktree`, and `getActiveTicketWorktree` procs
- `executeAssignedTicket` now calls `setActiveTicketWorktree` before running the agent (with `defer: clearActiveTicketWorktree()`)
- The `submit_pr` handler now runs `make test` via `runWorktreeMakeTest` before accepting:
  - On pass: enqueues normally
  - On fail: returns error with truncated test output, does NOT call `recordSubmitPrSummary`
  - Logs `ticket <id>: submit_pr pre-check: PASS|FAIL (exit=<code>, wall=<duration>)`
  - Gracefully handles missing active worktree (skips test gate)

**Changes in `tests/test_scriptorium.nim`:**
- Added test "submit_pr runs make test and enqueues on pass"
- Added test "submit_pr runs make test and rejects on failure"

All existing tests continue to pass, including the `executeAssignedTicket` tests that call `submit_pr` through the fake runner.
```

### Agent Stdout Tail
```text
- Added test \"submit_pr runs make test and rejects on failure\"\n\nAll existing tests continue to pass, including the `executeAssignedTicket` tests that call `submit_pr` through the fake runner.","stop_reason":"end_turn","session_id":"2ee9aa8b-525a-446e-9c45-c784ae6fa95a","total_cost_usd":1.36210895,"usage":{"input_tokens":42,"cache_creation_input_tokens":43048,"cache_read_input_tokens":1516718,"output_tokens":10344,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":43048,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":42,"outputTokens":10344,"cacheReadInputTokens":1516718,"cacheCreationInputTokens":43048,"webSearchRequests":0,"costUSD":1.286219,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":59,"outputTokens":5077,"cacheReadInputTokens":173972,"cacheCreationInputTokens":26439,"webSearchRequests":0,"costUSD":0.07588995000000001,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"0cb18694-2198-4683-a0df-d0055d2f5387"}
```

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0040-pre-submit-test-gate/.scriptorium/logs/0040/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0040-pre-submit-test-gate/.scriptorium/logs/0040/attempt-02.last_message.txt\n
### Agent Last Message
```text
The PR has been submitted successfully. The implementation adds a pre-submit test gate to the `submit_pr` MCP tool handler that:

- Runs `make test` in the agent's worktree before accepting submissions
- Returns error with truncated test output on failure (without enqueuing)
- Enqueues normally on success
- Logs with ticket ID, pass/fail, exit code, and wall time
- Uses thread-safe shared variables for worktree path and ticket ID
- Includes unit tests for both pass and fail paths
```

### Agent Stdout Tail
```text
 pre-submit test gate to the `submit_pr` MCP tool handler that:\n\n- Runs `make test` in the agent's worktree before accepting submissions\n- Returns error with truncated test output on failure (without enqueuing)\n- Enqueues normally on success\n- Logs with ticket ID, pass/fail, exit code, and wall time\n- Uses thread-safe shared variables for worktree path and ticket ID\n- Includes unit tests for both pass and fail paths","stop_reason":"end_turn","session_id":"1da2ff8b-97e7-4760-8b3d-71b24209251b","total_cost_usd":0.31758425,"usage":{"input_tokens":16,"cache_creation_input_tokens":18175,"cache_read_input_tokens":304871,"output_tokens":2059,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":18175,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":16,"outputTokens":2059,"cacheReadInputTokens":304871,"cacheCreationInputTokens":18175,"webSearchRequests":0,"costUSD":0.31758425,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"a04fb75a-fefa-4384-a010-098ef136ba5f"}
```

## Merge Queue Success
- Summary: Add pre-submit test gate in submit_pr MCP tool handler. The handler now runs make test in the agent worktree before accepting submissions. Failing tests return error to agent without enqueuing. Thread-safe shared variables track active worktree path and ticket ID. Unit tests cover both pass and fail paths.\n
### Quality Check Output
```text
820f98a8c30a4d9/worktrees/tickets/0001-first)
[2026-03-13T01:41:26Z] [INFO] ticket 0001: merge queue entered (position=1)
[2026-03-13T01:41:26Z] [WARN] master is unhealthy — skipping tick
[2026-03-13T01:41:56Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=2 tickets_reopened=3 tickets_parked=0 merge_queue_processed=2
[2026-03-13T01:41:56Z] [INFO] session summary: avg_ticket_wall=0s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
[2026-03-13T01:41:56Z] [INFO] architect: generating areas from spec
[2026-03-13T01:41:57Z] [INFO] architect: areas updated
[2026-03-13T01:41:57Z] [INFO] manager: generating tickets
[2026-03-13T01:41:57Z] [INFO] merge queue: processing
[2026-03-13T01:41:57Z] [INFO] ticket 0001: merge started (make test running)
[2026-03-13T01:41:57Z] [INFO] ticket 0001: merge succeeded (test wall=0s)
[2026-03-13T01:41:57Z] [INFO] ticket 0001: in-progress -> done (total wall=31s, attempts=0)
[2026-03-13T01:41:57Z] [INFO] ticket 0001: post-analysis skipped (no prediction section)
[2026-03-13T01:41:57Z] [INFO] merge queue: item processed
[2026-03-13T01:41:57Z] [INFO] tick 0 summary: architect=updated manager=no-op coding=idle merge=processing open=0 in-progress=0 done=1
[2026-03-13T01:41:57Z] [INFO] session summary: uptime=1s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-13T01:41:57Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-10 global halt while red resumes after master health is restored
[2026-03-13T01:41:58Z] [WARN] master is unhealthy — skipping tick
[2026-03-13T01:42:28Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-13T01:42:28Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-11 integration-test failure on master blocks assignment of open tickets
```

## Metrics
- wall_time_seconds: 1058
- coding_wall_seconds: 734
- test_wall_seconds: 312
- attempt_count: 2
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 1362482

## Post-Analysis
- actual_difficulty: hard
- prediction_accuracy: underestimated
- brief_summary: Predicted medium, actual was hard with 2 attempt(s) in 17m38s.
