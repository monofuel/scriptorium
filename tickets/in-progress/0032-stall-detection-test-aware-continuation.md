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
