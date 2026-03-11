# Test-Aware Stall Detection

**Area:** stall-detection

## Problem

After ticket 0031 adds basic stall retry, the continuation prompt should be augmented with test results before being sent. Currently no test-aware stall detection exists.

## Requirements

Depends on 0031 (basic stall retry) being implemented first.

- When a stall is detected (turn ended, no `submit_pr` called), before sending the continuation prompt the orchestrator must:
  - Run `make test` in the agent's worktree.
  - Capture the exit code and output.
- If tests fail, the continuation prompt must include:
  - The test failure output (truncated to a reasonable limit if very long).
  - A directive to fix the failing tests before submitting.
- If tests pass, the continuation prompt must include:
  - A note that tests are passing.
  - A directive to continue working and call `submit_pr`.
- This augments the basic stall detection from 0031 — it does not replace it.
- Test-aware detection runs `make test` only, not `make integration-test`.

## Acceptance Criteria

- On stall, `make test` runs in the agent worktree before retry.
- Test failure output is included in the continuation prompt when tests fail (truncated if long).
- Test pass status is included in the continuation prompt when tests pass.
- The basic stall detection behavior from 0031 is preserved.
- Unit tests cover both the test-pass and test-fail branches of the stall continuation.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0032-stall-detection-test-aware-continuation

## Agent Run
- Model: claude-sonnet-4-6\n- Backend: claude-code\n- Exit Code: 137\n- Attempt: 2\n- Attempt Count: 2\n- Timeout: hard\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0032-stall-detection-test-aware-continuation/.scriptorium/logs/0032/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0032-stall-detection-test-aware-continuation/.scriptorium/logs/0032/attempt-02.last_message.txt\n
### Agent Last Message
```text
Now pass the builder through in both harness branches in agent_runner.nim:
```

### Agent Stdout Tail
```text
callback.\n        if not request.onEvent.isNil:\n          request.onEvent(mapClaudeCodeEvent(event))\n    ))\n    result = AgentRunResult(\n      backend: request.harness,\n      command: claudeResult.command,\n      exitCode: claudeResult.exitCode,\n      attempt: claudeResult.attempt,\n      attemptCount: claudeResult.attemptCount,\n      stdout: claudeResult.stdout,\n      logFile: claudeResult.logFile,\n      lastMessageFile: claudeResult.lastMessageFile,\n      lastMessage: claudeResult.lastMessage,\n      timeoutKind: $claudeResult.timeoutKind,\n    )\n  else:\n    raise newException(ValueError, &\"agent backend '{request.harness}' is not implemented\")\n","structuredPatch":[{"oldStart":112,"oldLines":6,"newStart":112,"newLines":7,"lines":["       heartbeatIntervalMs: request.heartbeatIntervalMs,","       maxAttempts: request.maxAttempts,","       continuationPrompt: request.continuationPrompt,","+      continuationPromptBuilder: request.continuationPromptBuilder,","       onEvent: proc(event: CodexStreamEvent) =","         ## Forward codex streaming events to the optional agent callback.","         if not request.onEvent.isNil:"]}],"userModified":false,"replaceAll":false}}
```

## Agent Run
- Model: claude-sonnet-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0032-stall-detection-test-aware-continuation/.scriptorium/logs/0032/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0032-stall-detection-test-aware-continuation/.scriptorium/logs/0032/attempt-01.last_message.txt\n
### Agent Last Message
```text
All tests passed, including both new test-aware stall detection tests. The background task confirms:
- `[OK] executeAssignedTicket includes passing test status in stall continuation prompt`
- `[OK] executeAssignedTicket includes failing test output in stall continuation prompt`
```

### Agent Stdout Tail
```text
ebdcac"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":13108,"duration_api_ms":398821,"num_turns":2,"result":"All tests passed, including both new test-aware stall detection tests. The background task confirms:\n- `[OK] executeAssignedTicket includes passing test status in stall continuation prompt`\n- `[OK] executeAssignedTicket includes failing test output in stall continuation prompt`","stop_reason":"end_turn","session_id":"81db8cbd-4e7b-456d-adbc-c9301ca6d469","total_cost_usd":2.5553049999999997,"usage":{"input_tokens":4,"cache_creation_input_tokens":878,"cache_read_input_tokens":138635,"output_tokens":176,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":878,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-sonnet-4-6":{"inputTokens":83,"outputTokens":14578,"cacheReadInputTokens":3619930,"cacheCreationInputTokens":60876,"webSearchRequests":0,"costUSD":2.5553049999999997,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"5e749ef9-e3d1-463b-8da3-71c352ba1b84"}
```

## Merge Queue Failure
- Summary: add test-aware stall detection: run make test before retry prompt, include test pass/fail status in continuation message\n
### Merge Output
```text
fatal: not a git repository: /workspace/.git/worktrees/0032-stall-detection-test-aware-continuation
```
