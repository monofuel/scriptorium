# Unit tests for coding agent log forwarding handler

**Area:** log-forwarding
**ID:** 0119
**Depends:** 0118

## Description

Add unit tests for the `buildCodingEventHandler` proc created in ticket 0118.

### Test file

Create `tests/test_coding_event_handler.nim`. Follow existing test patterns (see `tests/test_agent_runner.nim` for reference). The file must import from `src/scriptorium/coding_agent` and `src/scriptorium/agent_runner`.

Tests must have `--path:"../src"` available via `tests/config.nims` (already configured).

### Test cases

1. **Tool event logging format**: Verify that a tool event with `text: "Edit src/foo.nim"` produces a log line containing `coding[0042]: tool Edit src/foo.nim`.

2. **File write detection**: Verify that tool events with write-like tool names (`Edit`, `Write`, `edit_file`, `write_file`, `NotebookEdit`) produce a file activity log line like `coding[0042]: file write src/foo.nim`.

3. **File read detection**: Verify that tool events with read-like tool names (`Read`, `read_file`, `Grep`, `Glob`) produce a file activity log line like `coding[0042]: file read src/foo.nim`.

4. **Status event logging**: Verify that a status event produces `coding[0042]: status thinking`.

5. **Heartbeat events are not logged to stdout**: Verify heartbeat events do not produce stdout output (they may be logged to file only, or ignored).

6. **Unknown tool names**: Verify that a tool event with an unrecognized tool name (e.g., `Bash ls -la`) logs the tool event but does NOT produce a file activity line.

### Testing approach

Since `logDebug` writes to stdout and a file, capture stdout output in tests using a string buffer or by checking the log file. Alternatively, refactor the handler to accept a logging callback for testability — if this approach is simpler, the test file may define a mock logger that collects messages into a `seq[string]`.

### Key files

- `tests/test_coding_event_handler.nim` — new test file
- `src/scriptorium/coding_agent.nim` — proc under test
- `src/scriptorium/agent_runner.nim` — event types

### Notes

- Run tests with `nim r tests/test_coding_event_handler.nim`.
- Follow project convention: no mocks of core dependencies in unit tests, but a logging callback abstraction is acceptable since it's testing the handler's classification logic, not the logging system.
