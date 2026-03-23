# 0085-test-exit-command-plan-ask.md

# Test /exit command works in plan and ask sessions

**Area:** planning-sessions

## Goal

Add unit tests verifying that `/exit` exits the session without invoking the runner, just like `/quit`, in both interactive plan and ask sessions.

## Context

The spec (Section 2) requires both `/quit` and `/exit` to leave the session. The implementation handles both at `src/scriptorium/interactive_sessions.nim` lines 75-76 (plan) and lines 193-194 (ask). However, existing tests only use `/quit` — `/exit` is never tested.

## Tasks

1. In `tests/test_orchestrator_flow.nim`, add a test to the `"interactive planning"` suite:
   - Send `/exit` as the only input
   - Verify the runner is never called
   - Verify the session exits cleanly (no error raised)

2. Add an equivalent test to the `"interactive ask session"` suite for `/exit`.

Follow the existing slash-command test patterns (see the `/show, /help, /quit do not invoke runner` tests).
