# 0084-test-unknown-slash-commands.md

# Test unknown slash commands rejected in plan and ask sessions

**Area:** planning-sessions

## Goal

Add unit tests verifying that unknown slash commands (e.g. `/foo`, `/status`) are rejected without invoking the Architect agent runner, in both interactive plan and ask sessions.

## Context

The spec (Section 2) requires: "unknown slash commands without invoking the Architect." The implementation handles this correctly in `src/scriptorium/interactive_sessions.nim` (lines 91-95 for plan, lines 209-213 for ask), but no test explicitly validates this behavior. The existing tests at `tests/test_orchestrator_flow.nim` only test `/show`, `/help`, and `/quit`.

## Tasks

1. In `tests/test_orchestrator_flow.nim`, add a test to the `"interactive planning"` suite that:
   - Sends an unknown slash command like `/foo`, then `/quit`
   - Verifies the agent runner is never called (`callCount == 0`)
   - Verifies no commits are created

2. Add an equivalent test to the `"interactive ask session"` suite that:
   - Sends `/unknown`, then `/quit`
   - Verifies the agent runner is never called
   - Verifies no commits are created

Follow the existing test patterns in the file (use `makeTestRepo`, `runInit`, `fakeRunner`, `fakeInput`, `quiet = true`).

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0086-0084-test-unknown-slash-commandsmd

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 10
- reasoning: Adding two simple unit tests to an existing test file following established patterns, single file change with no logic complexity.
