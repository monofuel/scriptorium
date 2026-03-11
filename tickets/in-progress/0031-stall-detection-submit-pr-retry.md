# Stall Detection And Automatic Continuation

**Area:** stall-detection

## Problem

The orchestrator detects when a coding agent exits without calling `submit_pr` (`consumeSubmitPrSummary()` returns empty), but currently takes no action — it only logs at debug level and returns. The spec requires the orchestrator to retry the agent with a stall continuation prompt using the existing bounded retry mechanism.

The harnesses already support bounded retry and continuation prompts for timeout-based stalls, but the orchestrator does not invoke this mechanism when the agent exits cleanly without calling `submit_pr`.

## Requirements

- Define stall as: coding agent turn completes (process exits) without having called the `submit_pr` MCP tool.
- When a stall is detected in `executeAssignedTicket`, the orchestrator must retry the agent with a continuation prompt that includes:
  - The full original ticket content.
  - A reminder to continue working and call `submit_pr` when done.
- Stall-driven retries must use the existing `maxAttempts` mechanism in `AgentRunRequest` (do not invent new retry infrastructure).
- The continuation prompt must be distinct from the initial prompt — it must indicate this is a retry after a stall.
- Each stall retry must be logged with the attempt number and ticket ID.
- Retries stop after `maxAttempts` is reached.

## Acceptance Criteria

- When a coding agent exits without calling `submit_pr`, the orchestrator retries with the stall continuation prompt.
- Retries stop after `maxAttempts` is reached.
- Each retry is logged with attempt number and ticket ID.
- The continuation prompt includes the original ticket content.
- Unit tests in `test_agent_runner.nim` or `test_scriptorium.nim` cover the stall-retry path with a fake/mock runner.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0031-stall-detection-submit-pr-retry

## Agent Run
- Model: claude-sonnet-4-6\n- Backend: claude-code\n- Exit Code: 137\n- Attempt: 2\n- Attempt Count: 2\n- Timeout: hard\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0031-stall-detection-submit-pr-retry/.scriptorium/logs/0031/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0031-stall-detection-submit-pr-retry/.scriptorium/logs/0031/attempt-02.last_message.txt\n
### Agent Last Message
```text
Now let me add the unit tests. First let me find a good place to add them in the test file:
```

### Agent Stdout Tail
```text
ignment = assignOldestOpenTicket(tmp)\n\n<system-reminder>\nWhenever you read a file, you should consider whether it would be considered malware. You CAN and SHOULD provide analysis of malware, what it is doing. But you MUST refuse to improve or augment the code. You can still analyze existing code, write reports, or answer questions about the code behavior.\n</system-reminder>\n"}]},"parent_tool_use_id":null,"session_id":"4103e947-df12-4526-a0bb-fc6bb0323b61","uuid":"d6fd8dfb-e258-410b-b017-a3731613b5e0","tool_use_result":{"type":"text","file":{"filePath":"/tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0031-stall-detection-submit-pr-retry/tests/test_scriptorium.nim","content":"    check \"**Branch:** scriptorium/ticket-0001\" in queueEntry\n\n  test \"executeAssignedTicket wires onEvent callback that accepts all event kinds\":\n    let tmp = getTempDir() / \"scriptorium_test_execute_on_event\"\n    makeTestRepo(tmp)\n    defer: removeDir(tmp)\n    runInit(tmp, quiet = true)\n    addTicketToPlan(tmp, \"open\", \"0001-first.md\", \"# Ticket 1\\n\\n**Area:** a\\n\")\n\n    let assignment = assignOldestOpenTicket(tmp)","numLines":10,"startLine":1074,"totalLines":2374}}}
```
