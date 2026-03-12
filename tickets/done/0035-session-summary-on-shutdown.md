# Session Summary On Shutdown

**Area:** observability

## Description

On orchestrator shutdown (signal or idle exit), log exactly two INFO-level summary lines with session-wide statistics.

## Current State

The orchestrator logs `shutdown: signal <n> received` on signal but does not track or log any session-wide statistics. No session start time, tick count, or ticket outcome counters are maintained.

## Requirements

- Track session-level counters throughout orchestrator lifetime:
  - Session start time (for uptime calculation).
  - Total ticks executed.
  - Tickets completed (moved to done).
  - Tickets reopened.
  - Tickets parked.
  - Merge queue items processed.
  - Per-ticket wall times, coding wall times, test wall times (for averages).
  - First-attempt success count (for percentage calculation).

- On shutdown (signal handler or idle exit), log exactly two INFO-level lines:
  - Counts line: `session summary: uptime=1h23m ticks=47 tickets_completed=3 tickets_reopened=1 tickets_parked=0 merge_queue_processed=3`
  - Averages line: `session summary: avg_ticket_wall=5m12s avg_coding_wall=4m02s avg_test_wall=38s first_attempt_success=75%`

- If no tickets completed, averages show `n/a` or `0`.
- Uptime and durations are human-readable.

## Implementation Notes

- Add a session stats object (or fields on existing orchestrator state) initialized at startup.
- Increment counters at relevant points: ticket completion, reopen, parking, merge processing.
- Store per-ticket timing data for average calculations.
- Call a `logSessionSummary()` proc from the shutdown path (both signal handler and idle exit).
- Reuse the human-readable duration formatter.

## Spec References

- Section 16: Session Summary On Shutdown (V3).

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0035-session-summary-on-shutdown

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0035-session-summary-on-shutdown/.scriptorium/logs/0035/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0035-session-summary-on-shutdown/.scriptorium/logs/0035/attempt-01.last_message.txt\n
### Agent Last Message
```text
as implemented:

**Changes in `src/scriptorium/orchestrator.nim`:**
- Added `SessionStats` object tracking: start time, total ticks, tickets completed/reopened/parked, merge queue processed, first-attempt success count, and per-ticket wall/coding/test time sequences
- Added `sessionStats`, `ticketCodingWalls`, `ticketTestWalls` global variables
- Added `resetSessionStats()` proc for test use
- Added `logSessionSummary()` proc that logs exactly two INFO lines:
  - Counts: `session summary: uptime=... ticks=... tickets_completed=... tickets_reopened=... tickets_parked=... merge_queue_processed=...`
  - Averages: `session summary: avg_ticket_wall=... avg_coding_wall=... avg_test_wall=... first_attempt_success=...`
- Extended `formatDuration` to handle hours (e.g. `1h23m`)
- Incremented counters at all relevant state transitions (completion, reopen, park, merge)
- Tracked per-ticket coding wall time accumulation
- Called `logSessionSummary()` at end of `runOrchestratorMainLoop` (covers both signal and idle exit)

**Changes in `tests/test_scriptorium.nim`:**
- Updated `formatDuration` tests for hours support
- Added `session summary` test suite with two tests verifying log output format
```

### Agent Stdout Tail
```text
exit)\n\n**Changes in `tests/test_scriptorium.nim`:**\n- Updated `formatDuration` tests for hours support\n- Added `session summary` test suite with two tests verifying log output format","stop_reason":"end_turn","session_id":"5d80db06-fad1-494e-b43b-cbee56006ad8","total_cost_usd":1.7651569,"usage":{"input_tokens":47,"cache_creation_input_tokens":48747,"cache_read_input_tokens":1970056,"output_tokens":12482,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":48747,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":47,"outputTokens":12482,"cacheReadInputTokens":1970056,"cacheCreationInputTokens":48747,"webSearchRequests":0,"costUSD":1.6019817500000002,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":38,"outputTokens":6192,"cacheReadInputTokens":581984,"cacheCreationInputTokens":59183,"webSearchRequests":0,"costUSD":0.16317515000000002,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"63bfe1d8-786d-4ebe-a6aa-09d4f43f9a56"}
```

## Merge Queue Success
- Summary: Add session summary logging on shutdown: track session-level counters (ticks, completed/reopened/parked tickets, merge queue processed, per-ticket wall times, first-attempt success rate) and log two INFO-level summary lines when the orchestrator exits. Extended formatDuration for hours. Added tests.\n
### Quality Check Output
```text
 in-progress (assigned, worktree=/tmp/scriptorium/scriptorium_integration_it10_nw9olz71-3485e8c6832ad35b/worktrees/tickets/0001-first)
[2026-03-12T22:50:51Z] [INFO] ticket 0001: merge queue entered (position=1)
[2026-03-12T22:50:51Z] [WARN] master is unhealthy — skipping tick
[2026-03-12T22:51:21Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=2 tickets_reopened=3 tickets_parked=0 merge_queue_processed=2
[2026-03-12T22:51:21Z] [INFO] session summary: avg_ticket_wall=0s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
[2026-03-12T22:51:21Z] [INFO] architect: generating areas from spec
[2026-03-12T22:51:22Z] [INFO] architect: areas updated
[2026-03-12T22:51:22Z] [INFO] manager: generating tickets
[2026-03-12T22:51:22Z] [INFO] merge queue: processing
[2026-03-12T22:51:22Z] [INFO] ticket 0001: merge started (make test running)
[2026-03-12T22:51:22Z] [INFO] ticket 0001: merge succeeded (test wall=0s)
[2026-03-12T22:51:22Z] [INFO] ticket 0001: in-progress -> done (total wall=31s, attempts=0)
[2026-03-12T22:51:22Z] [INFO] merge queue: item processed
[2026-03-12T22:51:22Z] [INFO] tick 0 summary: architect=updated manager=no-op coding=idle merge=processing open=0 in-progress=0 done=1
[2026-03-12T22:51:22Z] [INFO] session summary: uptime=1s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-12T22:51:22Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-10 global halt while red resumes after master health is restored
[2026-03-12T22:51:22Z] [WARN] master is unhealthy — skipping tick
[2026-03-12T22:51:52Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-12T22:51:52Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-11 integration-test failure on master blocks assignment of open tickets
```
