# 0127 — Enhance coding agent event handler to log all event types

**Area:** log-forwarding

**Problem:** The current `onEvent` handler in `coding_agent.nim:190-194` only logs `agentEventTool` and `agentEventStatus` events at debug level. Heartbeat and message events are silently dropped. The area spec requires all existing event categories to be surfaced.

**Task:**

Update the `onEvent` callback in `src/scriptorium/coding_agent.nim` (around line 190) to handle all five `AgentStreamEventKind` values:

- `agentEventTool` — already logged, keep as-is for now (will be refined in ticket 0128)
- `agentEventStatus` — already logged, keep as-is
- `agentEventHeartbeat` — add `logDebug(fmt"coding[{ticketId}]: heartbeat")`
- `agentEventMessage` — add `logDebug(fmt"coding[{ticketId}]: message {event.text}")` (truncate text to ~120 chars to avoid log spam)
- `agentEventReasoning` — skip logging (reasoning text is verbose and not operationally useful)

Use the existing `logDebug` from `src/scriptorium/logging.nim`. The `ticketId` is already captured in the closure.

**Acceptance:**
- All five event kinds have explicit handling (even if some are no-ops)
- `make test` passes
- No new dependencies added
````

---

````markdown
# 0128 — Extract and log file activity from tool events

**Area:** log-forwarding

**Problem:** The area spec requires logging file reads and writes detected from tool events (e.g., `coding[0003]: read src/foo.nim`, `coding[0003]: write src/bar.nim`). Currently, tool events are logged as raw text like `edit_file src/foo.nim` without distinguishing file activity from other tool calls.

**Task:**

In `src/scriptorium/coding_agent.nim`, enhance the `onEvent` callback's `agentEventTool` branch to detect file-related tool calls and log them with a `file` prefix.

The `event.text` field already contains the tool name followed by an arg summary (e.g., `Read src/foo.nim`, `Edit src/bar.nim`, `Write src/baz.nim`, `Bash echo hello`). This is built by `extractToolArgSummary` in `src/scriptorium/harness_claude_code.nim:219` and `resolveCodexToolArgSummary` in `src/scriptorium/harness_codex.nim`.

Logic:
1. Parse the tool name from `event.text` (first whitespace-delimited token, case-insensitive).
2. If the tool name matches a file-activity tool (`Read`, `Edit`, `Write`, `edit_file`, `read_file`, `write_file`, `Glob`, `Grep`), log: `logDebug(fmt"coding[{ticketId}]: file {event.text}")`.
3. For all tool events (including file ones), continue logging the existing line: `logDebug(fmt"coding[{ticketId}]: tool {event.text}")`.

This gives operators both a file-activity stream and a full tool stream in the logs.

**Acceptance:**
- File-related tool events produce an additional `file` log line
- Non-file tool events (e.g., `Bash`, `submit_pr`) only produce the `tool` line
- `make test` passes
````

---

````markdown
# 0129 — Add unit tests for coding agent log forwarding

**Area:** log-forwarding

**Depends:** 0127, 0128

**Problem:** The event forwarding logic in the `onEvent` callback has no unit test coverage. Changes to event handling should be verified automatically.

**Task:**

Create or extend a test in `tests/test_coding_agent.nim` (or a new `tests/test_log_forwarding.nim` if no suitable file exists) that exercises the event handler logic.

Approach:
1. Construct `AgentStreamEvent` values for each kind (heartbeat, tool, status, message, reasoning).
2. For tool events, include both file-related (`Edit src/foo.nim`) and non-file (`Bash echo hello`) text.
3. Capture log output (or refactor the handler into a testable proc that returns log lines instead of calling `logDebug` directly).
4. Assert expected log lines are produced for each event kind.

Use the existing test infrastructure: `tests/config.nims` already has `--path:"../src"` for imports. Follow the project convention of `tests/test_*.nim` for unit tests. Do not use mocks for external services — this is a pure unit test of log-line formatting logic.

**Acceptance:**
- Tests cover all five event kinds
- Tests verify file-activity detection for tool events
- `make test` passes including the new tests
````

---

These three tickets cover the full scope of the log-forwarding area: surfacing all event types (0127), extracting file activity (0128), and test coverage (0129). The work is already well-supported by existing infrastructure — the `AgentEventHandler` callback, event parsing in both harnesses, and the logging module are all in place. The tickets focus on the gap: enhancing the consumer-side handler in `coding_agent.nim`.
