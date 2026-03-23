# 0086-test-multi-turn-plan-history-and-commits.md

# Test multi-turn plan session history in prompts and commit messages

**Area:** planning-sessions

## Goal

Add a unit test verifying that a multi-turn interactive planning session correctly:
1. Includes prior turn history in subsequent architect prompts
2. Creates commits with correct sequential turn numbers (`turn 1`, `turn 2`)

## Context

The spec (Section 2) requires "in-memory turn history for the current session" and commit messages of the form `scriptorium: plan session turn <n>`. The existing tests only cover single-turn scenarios. The ask session has a history test (`"ask prompt includes conversation history"`) but the plan session has no equivalent end-to-end multi-turn test.

## Tasks

In `tests/test_orchestrator_flow.nim`, add a test to the `"interactive planning"` suite that:

1. Creates a test repo with `makeTestRepo` and `runInit`
2. Uses a `fakeRunner` that:
   - On call 1: writes new spec content, captures the prompt, returns a response
   - On call 2: writes different spec content, captures the prompt, returns a response
3. Uses a `fakeInput` that yields two messages then raises `EOFError`
4. Calls `runInteractivePlanSession` with `quiet = true`
5. Asserts:
   - `callCount == 2`
   - The second call's prompt contains the first turn's user message and architect response (history)
   - Plan branch log contains both `"plan session turn 1"` and `"plan session turn 2"`

Follow the existing test patterns in the file. Use `planCommitCount` or `latestPlanCommits` helpers from `tests/helpers.nim` as needed.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0088-0086-test-multi-turn-plan-history-and-commitsmd
