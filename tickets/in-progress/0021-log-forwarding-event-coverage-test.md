# Test coding agent log forwarding event coverage

The spec (Section 10) requires that during coding agent execution, tool calls, file activity, and status changes are forwarded to orchestrator logs with ticket ID prefix. There is no dedicated test verifying that the `onEvent` callback in `executeAssignedTicket` forwards the correct event types with the expected log format.

## Current state

The existing `executeAssignedTicket` test at `tests/test_scriptorium.nim:972` uses a fake runner but does not verify:
- Which event kinds the `onEvent` callback accepts (tool, status).
- Which event kinds the callback ignores (heartbeat, reasoning, message).
- That log output includes the ticket ID prefix format `coding[{ticketId}]:`.

## Task

Add a dedicated test in `tests/test_scriptorium.nim` that verifies the `onEvent` callback wired by `executeAssignedTicket` forwards the correct event types. The test should:

1. Capture the `onEvent` callback from the `AgentRunRequest` passed to the fake runner.
2. Fire synthetic events of each kind (`agentEventTool`, `agentEventStatus`, `agentEventHeartbeat`, `agentEventReasoning`, `agentEventMessage`) through the callback.
3. Verify that tool and status events are accepted without error.
4. Verify that the callback is not nil (already checked in existing tests, but confirm in context of this test).

Since `logDebug` writes to stdout/file and is hard to capture in unit tests, the test should focus on verifying:
- The callback is wired (not nil).
- The callback does not raise when called with expected event types.
- The callback can be called with all five event kinds without crashing.

## Files

- `tests/test_scriptorium.nim` — add test near existing `executeAssignedTicket` tests
- `src/scriptorium/orchestrator.nim:1857` — `onEvent` callback (reference)
- `src/scriptorium/agent_runner.nim:6` — `AgentStreamEventKind` enum (reference)

## Acceptance criteria

- New test verifies `onEvent` is wired and callable with all event kinds.
- Test fires tool and status events through the callback without error.
- `make test` passes.

**Area:** log-forwarding

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0021-log-forwarding-event-coverage-test
