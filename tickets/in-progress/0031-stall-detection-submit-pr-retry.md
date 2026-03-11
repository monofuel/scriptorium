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

## Agent Run
- Model: claude-sonnet-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0031-stall-detection-submit-pr-retry/.scriptorium/logs/0031/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0031-stall-detection-submit-pr-retry/.scriptorium/logs/0031/attempt-01.last_message.txt\n
### Agent Last Message
```text
 a stall-specific message indicating this is a retry
   - Refactored `executeAssignedTicket` to use a `while` loop that:
     - Tracks `totalAttemptsUsed` across all runs
     - Passes `maxAttempts: DefaultAgentMaxAttempts - totalAttemptsUsed` to each runner call (so total attempts never exceed the bound)
     - After each run, detects a stall (`exitCode == 0`, `timeoutKind == "none"`, no `submit_pr`)
     - If stall and attempts remain, logs the retry with attempt/ticket info and retries with the stall continuation prompt
     - Stops after `maxAttempts` is reached and reopens the ticket

2. **`tests/test_scriptorium.nim`:**
   - Updated "runs agent and appends run summary" test (now expects 2 runner calls and 3 plan commits due to stall retry)
   - Updated "orchestrator tick assigns and executes before merge queue" test (now expects 5 plan commits)
   - Added **"executeAssignedTicket retries stalled agent with continuation prompt"** — verifies retry happens, continuation prompt includes ticket content and stall indicator, and succeeds on second call
   - Added **"executeAssignedTicket stops stall retries after maxAttempts"** — verifies retries stop at 2 and ticket is reopened
```

### Agent Stdout Tail
```text
cutes before merge queue\" test (now expects 5 plan commits)\n   - Added **\"executeAssignedTicket retries stalled agent with continuation prompt\"** — verifies retry happens, continuation prompt includes ticket content and stall indicator, and succeeds on second call\n   - Added **\"executeAssignedTicket stops stall retries after maxAttempts\"** — verifies retries stop at 2 and ticket is reopened","stop_reason":"end_turn","session_id":"9728569c-0433-4fce-b0a3-8b1817edcdf7","total_cost_usd":4.2666552499999995,"usage":{"input_tokens":90,"cache_creation_input_tokens":78559,"cache_read_input_tokens":5702423,"output_tokens":36960,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":78559,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-sonnet-4-6":{"inputTokens":90,"outputTokens":36960,"cacheReadInputTokens":5702423,"cacheCreationInputTokens":78559,"webSearchRequests":0,"costUSD":4.2666552499999995,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"97a4ff9e-05b7-4690-baf5-7fc6575a314c"}
```

## Merge Queue Failure
- Summary: Add stall detection and retry in executeAssignedTicket: detects clean agent exits without submit_pr, retries with continuation prompt up to maxAttempts, with unit tests\n
### Merge Output
```text
fatal: not a git repository: /workspace/.git/worktrees/0031-stall-detection-submit-pr-retry
```

## Agent Run
- Model: claude-sonnet-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0031-stall-detection-submit-pr-retry/.scriptorium/logs/0031/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0031-stall-detection-submit-pr-retry/.scriptorium/logs/0031/attempt-01.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` MCP tool was called successfully. The orchestrator responded with "Merge request enqueued."

**Summary:** The previous agent (attempt 1) had already implemented all the required functionality and committed it. Tests pass. The merge failure was due to a git worktree path issue, not a code problem. I've now called `submit_pr` to signal the orchestrator to enqueue the changes for merge.

The implementation includes:
- Stall detection in `executeAssignedTicket` (clean exit with exit code 0, no `submit_pr` call)
- Retry with continuation prompt that includes original ticket content and stall indicator
- Uses existing `maxAttempts` mechanism (no new retry infrastructure)
- Logs each retry with attempt number and ticket ID
- Unit tests covering stall retry path and max attempts cutoff
```

### Agent Stdout Tail
```text
hanges for merge.\n\nThe implementation includes:\n- Stall detection in `executeAssignedTicket` (clean exit with exit code 0, no `submit_pr` call)\n- Retry with continuation prompt that includes original ticket content and stall indicator\n- Uses existing `maxAttempts` mechanism (no new retry infrastructure)\n- Logs each retry with attempt number and ticket ID\n- Unit tests covering stall retry path and max attempts cutoff","stop_reason":"end_turn","session_id":"c9939320-0a9c-4c59-97be-bfaaec9511fd","total_cost_usd":0.6988325,"usage":{"input_tokens":39,"cache_creation_input_tokens":20716,"cache_read_input_tokens":879325,"output_tokens":5180,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":20716,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-sonnet-4-6":{"inputTokens":39,"outputTokens":5180,"cacheReadInputTokens":879325,"cacheCreationInputTokens":20716,"webSearchRequests":0,"costUSD":0.6988325,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"a3059e90-af5d-40a6-a1f1-9c06ebf066f0"}
```
