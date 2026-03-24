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

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 46s

**Review Reasoning:** The changes are clean and correct. Both modifications follow the existing patterns exactly — adding `PlanTicketsStuckDir` as an additional branch in `ticketStateFromPath()` and as an additional pathspec in `transitionCountInCommit()`. The test follows the same conventions as other tests in the file.

Let me verify one minor thing — that `tickets/stuck/` directory is properly created during the test (since `runInit` only creates open/in-progress/done).
The test uses `moveFile` which will create the parent directory path implicitly via the git operations. Actually, `moveFile` in Nim requires the destination directory to exist. Let me check if `withPlanWorktree` + the `moveFile` call would work — the `tickets/stuck/` directory needs to exist in the plan worktree.
Let me check if `runInit` creates the `tickets/stuck/` directory.
Good — `runInit` creates `tickets/stuck/`. Now let me verify the test would actually work: `moveFile` requires the destination directory to exist, and since `runInit` creates it with a `.gitkeep`, the directory will exist in the plan worktree checkout. This looks correct.

The changes are minimal, correct, and follow existing patterns exactly:

1. **`ticketStateFromPath()`** — new `elif` branch matches the pattern of the three existing branches.
2. **`transitionCountInCommit()`** — `PlanTicketsStuckDir` added to the pathspec array, matching existing entries.
3. **Test** — follows the same structure as other tests: creates temp repo, initializes, adds ticket, performs transition in a plan worktree, validates. Uses existing helpers (`makeTestRepo`, `runInit`, `addTicketToPlan`, `withPlanWorktree`). Proper `defer: removeDir`.

No convention violations, no dead code, no unrelated changes.
Approved. The changes are clean, minimal, and correct — both source modifications follow the existing patterns exactly, and the test properly exercises the stuck-parking transition path.

## Merge Queue Failure
- Summary: Add PlanTicketsStuckDir to ticketStateFromPath() and transitionCountInCommit() so stuck-parking commits pass validation. Add unit test for stuck transition.\n- Failed gate: git merge master (ff-only and no-ff both failed)\n
### Merge Output
```text
Merge made by the 'ort' strategy.
 src/scriptorium/loop_system.nim | 20 +++++++++++
 tests/test_loop_system.nim      | 74 +++++++++++++++++++++++++++++++++++++++++
 2 files changed, 94 insertions(+)
 create mode 100644 src/scriptorium/loop_system.nim
 create mode 100644 tests/test_loop_system.nim
```

### Quality Check Output
```text
error: Your local changes to the following files would be overwritten by merge:
	src/scriptorium/ticket_assignment.nim
	tests/test_ticket_assignment.nim
Please commit your changes or stash them before you merge.
Aborting
Merge with strategy ort failed.
```

## Metrics
- wall_time_seconds: 2067
- coding_wall_seconds: 155
- test_wall_seconds: 0
- attempt_count: 1
- outcome: reopened
- failure_reason: test_failure
- model: claude-opus-4-6
- stdout_bytes: 333766

## Post-Analysis
- actual_difficulty: hard
- prediction_accuracy: underestimated
- brief_summary: Predicted easy, actual was hard with 1 attempt(s) in 34m27s.

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 13
- reasoning: Two small pattern-matched additions in a single source file plus a unit test following existing conventions; the merge conflict from master is minor but adds a couple minutes of resolution overhead.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0101/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0101/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes:

- **`src/scriptorium/ticket_assignment.nim`**: Added `PlanTicketsStuckDir` branch to `ticketStateFromPath()` and added `PlanTicketsStuckDir` to the `git diff` pathspec in `transitionCountInCommit()`.
- **`tests/test_ticket_assignment.nim`**: Added "stuck state transition validation" suite with a test that moves a ticket from in-progress to stuck with `MergeQueueStuckCommitPrefix` and verifies `validateTransitionCommitInvariant()` passes.
```

### Agent Stdout Tail
```text
PlanTicketsStuckDir` branch to `ticketStateFromPath()` and added `PlanTicketsStuckDir` to the `git diff` pathspec in `transitionCountInCommit()`.\n- **`tests/test_ticket_assignment.nim`**: Added \"stuck state transition validation\" suite with a test that moves a ticket from in-progress to stuck with `MergeQueueStuckCommitPrefix` and verifies `validateTransitionCommitInvariant()` passes.","stop_reason":"end_turn","session_id":"d676eac5-e320-481d-b8ce-8bb696c81c58","total_cost_usd":0.7350055000000001,"usage":{"input_tokens":9843,"cache_creation_input_tokens":48072,"cache_read_input_tokens":475531,"output_tokens":5903,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":48072},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":9843,"outputTokens":5903,"cacheReadInputTokens":475531,"cacheCreationInputTokens":48072,"webSearchRequests":0,"costUSD":0.7350055000000001,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"fca9072b-80aa-4840-a465-dabd517e478c"}
```
