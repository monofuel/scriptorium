# Add stuck state to ticket transition validation

**Area:** plan-state

## Problem

`ticketStateFromPath()` in `src/scriptorium/ticket_assignment.nim:67-75` recognizes `tickets/open/`, `tickets/in-progress/`, and `tickets/done/` but does NOT recognize `tickets/stuck/`. Similarly, `transitionCountInCommit()` at lines 86-101 only passes `PlanTicketsOpenDir`, `PlanTicketsInProgressDir`, and `PlanTicketsDoneDir` to `git diff --name-status` — it omits `PlanTicketsStuckDir`.

This means `validateTransitionCommitInvariant()` would incorrectly reject a valid stuck-parking commit: it sees `MergeQueueStuckCommitPrefix` as a transition subject via `isOrchestratorTransitionSubject()` (line 83), but `transitionCountInCommit()` returns 0 because the stuck directory is invisible, triggering the "must contain exactly one ticket transition (found 0)" error.

## Fix

1. In `ticketStateFromPath()` (`src/scriptorium/ticket_assignment.nim`), add an `elif` branch for `PlanTicketsStuckDir`.
2. In `transitionCountInCommit()`, add `PlanTicketsStuckDir` to the `git diff` pathspec list alongside the other three state directories.
3. Add a unit test in `tests/test_ticket_assignment.nim` that:
   - Creates a repo, initializes it, adds a ticket to `tickets/in-progress/`, then moves it to `tickets/stuck/` with a commit using `MergeQueueStuckCommitPrefix`.
   - Calls `validateTransitionCommitInvariant()` and verifies it passes without error.

## Files to modify

- `src/scriptorium/ticket_assignment.nim` — `ticketStateFromPath` and `transitionCountInCommit`
- `tests/test_ticket_assignment.nim` — new test case

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0101-add-stuck-state-to-ticket-transition-validation

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 11
- reasoning: Two small additions to existing pattern-matched branches in a single file plus a straightforward unit test, minimal integration risk.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0101/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0101/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes:

- **`src/scriptorium/ticket_assignment.nim`**: Added `PlanTicketsStuckDir` branch to `ticketStateFromPath()` (line 76-77) and added `PlanTicketsStuckDir` to the `git diff` pathspec in `transitionCountInCommit()` (line 103).
- **`tests/test_ticket_assignment.nim`**: Added "stuck state transition validation" suite with a test that moves a ticket from in-progress to stuck with `MergeQueueStuckCommitPrefix` and verifies `validateTransitionCommitInvariant()` passes.
```

### Agent Stdout Tail
```text
h to `ticketStateFromPath()` (line 76-77) and added `PlanTicketsStuckDir` to the `git diff` pathspec in `transitionCountInCommit()` (line 103).\n- **`tests/test_ticket_assignment.nim`**: Added \"stuck state transition validation\" suite with a test that moves a ticket from in-progress to stuck with `MergeQueueStuckCommitPrefix` and verifies `validateTransitionCommitInvariant()` passes.","stop_reason":"end_turn","session_id":"aec5f532-23a4-4fab-a786-c9e382599c6b","total_cost_usd":0.9873172499999999,"usage":{"input_tokens":4043,"cache_creation_input_tokens":47079,"cache_read_input_tokens":1066717,"output_tokens":5580,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":47079},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":4043,"outputTokens":5580,"cacheReadInputTokens":1066717,"cacheCreationInputTokens":47079,"webSearchRequests":0,"costUSD":0.9873172499999999,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"ea319b8b-b143-47aa-b490-79b5216686ff"}
```
