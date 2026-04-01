# 0092 Unit tests for log forwarding and file activity extraction

**Area:** log-forwarding
**Priority:** medium
**Depends:** 0090

## Summary

Add unit tests in `tests/test_log_forwarding.nim` for the `forwardAgentEvent` and `extractFileActivity` procs from `log_forwarding.nim`.

## Requirements

1. **Create `tests/test_log_forwarding.nim`.**

2. **Test `extractFileActivity`:**
   - Tool text containing `Read` with a file path returns `"read <path>"`.
   - Tool text containing `Edit` or `Write` with a file path returns `"write <path>"`.
   - Tool text containing `edit_file` or `write_file` returns appropriate activity.
   - Tool text with no file-related tool returns empty string.
   - Tool text with unrecognizable format returns empty string (graceful fallback).

3. **Test `forwardAgentEvent`:**
   - Use the `captureLogs` mechanism from `logging.nim` (set `captureLogs = true`, check `capturedLogs` after calls).
   - Tool event produces an INFO log line containing role, identifier, and tool text.
   - Status event produces an INFO log line containing role, identifier, and status text.
   - Heartbeat event produces no log output.
   - Reasoning event produces no log output.
   - Message event produces no log output.
   - File-related tool event produces both a tool log line and a file activity log line.

4. **Follow project test conventions:**
   - File is a unit test (`test_*.nim`), no real services or harnesses.
   - Uses `assert` or a lightweight check macro.
   - Import with bracket syntax: `std/[...]` then local modules.
   - The test file must have `tests/config.nims` path configuration (already exists).

5. **Run with `nim r tests/test_log_forwarding.nim`** — verify it compiles and passes.

## Acceptance Criteria

- All listed test cases exist and pass.
- Tests use `captureLogs` from logging module (no mocking of log output).
- Test file follows naming convention `tests/test_log_forwarding.nim`.
- No real agent processes or external services are invoked.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0100-0092-unit-tests-for-log-forwarding-and-file-activity-extraction

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Single new test file with straightforward assert-based unit tests against two pure procs, using an existing captureLogs mechanism — no cross-module integration risk, one attempt expected.
