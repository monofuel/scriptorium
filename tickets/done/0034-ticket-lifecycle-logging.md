# Ticket Lifecycle Logging

**Area:** observability

## Description

Add INFO-level log lines for every ticket state transition with timing, enabling full ticket lifecycle correlation via ticket ID.

## Current State

Some lifecycle events are already logged:
- Coding agent start/complete (`logInfo` for starting and completing ticket).
- Stall detection and continuation (`logInfo` for stall, pre-retry test pass/fail).
- PR submission (`logInfo` for submit_pr call).
- Some merge queue warnings (recovery, parking).

Missing lifecycle log points:
- Ticket assignment (open -> in-progress).
- Coding agent start with model/attempt details.
- Merge queue entry with position.
- Merge start (make test running).
- Merge success with test duration.
- Merge failure with reason.
- Ticket completion (in-progress -> done) with total wall time and attempt count.
- Ticket reopen (in-progress -> open) with reason, attempts, total wall time.

## Requirements

Add INFO-level log lines at each of the following points:

- Assignment: `ticket <id>: open -> in-progress (assigned, worktree=<path>)`
- Coding agent start: `ticket <id>: coding agent started (model=<model>, attempt <n>/<max>)`
- Coding agent finish: `ticket <id>: coding agent finished (exit=<code>, wall=<duration>, stall=<bool>)`
- PR submission: `ticket <id>: submit_pr called (summary="<summary>")`
- Merge queue entry: `ticket <id>: merge queue entered (position=<n>)`
- Merge start: `ticket <id>: merge started (make test running)`
- Merge success: `ticket <id>: merge succeeded (test wall=<duration>)`
- Merge failure: `ticket <id>: merge failed (reason=<reason>)`
- Completion: `ticket <id>: in-progress -> done (total wall=<duration>, attempts=<n>)`
- Reopen: `ticket <id>: in-progress -> open (reopened, reason=<reason>, attempts=<n>, total wall=<duration>)`

Stall-related (verify existing, update format if needed):
- Stall detection: `ticket <id>: coding agent stalled (attempt <n>/<max>, no submit_pr)`
- Pre-retry test: `ticket <id>: make test before retry: <PASS|FAIL> (exit=<code>, wall=<duration>)`
- Continuation: `ticket <id>: continuation prompt sent (attempt <n>/<max>, test_status=<passing|failing>)`

All lines must include ticket ID for correlation. Durations must be human-readable.

## Implementation Notes

- Add log lines at the relevant state transition points in `orchestrator.nim`.
- For wall time tracking on assignment->completion, store assignment start time (e.g., in a table or on the ticket state) and compute duration at completion/reopen.
- Reuse the human-readable duration formatter from the tick summary ticket.
- Update existing stall-related log lines to match the required format if they differ.

## Spec References

- Section 14: Ticket Lifecycle Logging (V3).

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0034-ticket-lifecycle-logging

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0034-ticket-lifecycle-logging/.scriptorium/logs/0034/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0034-ticket-lifecycle-logging/.scriptorium/logs/0034/attempt-01.last_message.txt\n
### Agent Last Message
```text
, worktree=<path>)`
2. **Coding agent start**: `ticket <id>: coding agent started (model=<model>, attempt <n>/<max>)`
3. **Coding agent finish**: `ticket <id>: coding agent finished (exit=<code>, wall=<duration>, stall=<bool>)`
4. **Stall detection**: `ticket <id>: coding agent stalled (attempt <n>/<max>, no submit_pr)` *(updated format)*
5. **Pre-retry test**: `ticket <id>: make test before retry: <PASS|FAIL> (exit=<code>, wall=<duration>)` *(updated format)*
6. **Continuation**: `ticket <id>: continuation prompt sent (attempt <n>/<max>, test_status=<passing|failing>)` *(new)*
7. **PR submission**: `ticket <id>: submit_pr called (summary="<summary>")` *(updated format)*
8. **Merge queue entry**: `ticket <id>: merge queue entered (position=<n>)`
9. **Merge start**: `ticket <id>: merge started (make test running)`
10. **Merge success**: `ticket <id>: merge succeeded (test wall=<duration>)`
11. **Merge failure**: `ticket <id>: merge failed (reason=<reason>)`
12. **Completion**: `ticket <id>: in-progress -> done (total wall=<duration>, attempts=<n>)`
13. **Reopen**: `ticket <id>: in-progress -> open (reopened, reason=<reason>, attempts=<n>, total wall=<duration>)`

All 154 tests pass.
```

### Agent Stdout Tail
```text
ted (make test running)`\n10. **Merge success**: `ticket <id>: merge succeeded (test wall=<duration>)`\n11. **Merge failure**: `ticket <id>: merge failed (reason=<reason>)`\n12. **Completion**: `ticket <id>: in-progress -> done (total wall=<duration>, attempts=<n>)`\n13. **Reopen**: `ticket <id>: in-progress -> open (reopened, reason=<reason>, attempts=<n>, total wall=<duration>)`\n\nAll 154 tests pass.","stop_reason":"end_turn","session_id":"35cc05b3-ee2e-45cb-841f-336fddb3f9f0","total_cost_usd":2.3827562500000004,"usage":{"input_tokens":58,"cache_creation_input_tokens":68899,"cache_read_input_tokens":3094895,"output_tokens":16176,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":68899,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":58,"outputTokens":16176,"cacheReadInputTokens":3094895,"cacheCreationInputTokens":68899,"webSearchRequests":0,"costUSD":2.3827562500000004,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"f2c0455e-28ca-4381-a9d9-dea09216656e"}
```

## Merge Queue Success
- Summary: Add INFO-level ticket lifecycle logging at all state transitions (assignment, coding agent start/finish, stall/retry, submit_pr, merge queue entry/start/success/failure, completion, reopen) with ticket ID correlation and human-readable wall time durations.\n
### Quality Check Output
```text
 test running)
[2026-03-12T22:33:20Z] [INFO] ticket 0001: merge failed (reason=git merge conflict)
[2026-03-12T22:33:20Z] [INFO] ticket 0001: in-progress -> open (reopened, reason=git merge conflict, attempts=0, total wall=0s)
  [OK] IT-05 merge conflict during merge master into ticket reopens ticket
[2026-03-12T22:33:21Z] [INFO] ticket 0001: open -> in-progress (assigned, worktree=/tmp/scriptorium/scriptorium_integration_it08_oeapsymi-ed7d848db3872d16/worktrees/tickets/0001-first)
[2026-03-12T22:33:21Z] [INFO] ticket 0001: merge queue entered (position=1)
  [OK] IT-08 recovery after partial queue transition converges without duplicate moves
[2026-03-12T22:33:21Z] [WARN] master is unhealthy — skipping tick
  [OK] IT-09 red master blocks assignment of open tickets
[2026-03-12T22:33:51Z] [INFO] ticket 0001: open -> in-progress (assigned, worktree=/tmp/scriptorium/scriptorium_integration_it10_7gtijlnq-13ce5ee8d67d72f0/worktrees/tickets/0001-first)
[2026-03-12T22:33:51Z] [INFO] ticket 0001: merge queue entered (position=1)
[2026-03-12T22:33:51Z] [WARN] master is unhealthy — skipping tick
[2026-03-12T22:34:21Z] [INFO] architect: generating areas from spec
[2026-03-12T22:34:22Z] [INFO] architect: areas updated
[2026-03-12T22:34:22Z] [INFO] manager: generating tickets
[2026-03-12T22:34:22Z] [INFO] merge queue: processing
[2026-03-12T22:34:22Z] [INFO] ticket 0001: merge started (make test running)
[2026-03-12T22:34:22Z] [INFO] ticket 0001: merge succeeded (test wall=0s)
[2026-03-12T22:34:22Z] [INFO] ticket 0001: in-progress -> done (total wall=31s, attempts=0)
[2026-03-12T22:34:22Z] [INFO] merge queue: item processed
[2026-03-12T22:34:22Z] [INFO] tick 0 summary: architect=updated manager=no-op coding=idle merge=processing open=0 in-progress=0 done=1
  [OK] IT-10 global halt while red resumes after master health is restored
[2026-03-12T22:34:23Z] [WARN] master is unhealthy — skipping tick
  [OK] IT-11 integration-test failure on master blocks assignment of open tickets
```
