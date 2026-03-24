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
