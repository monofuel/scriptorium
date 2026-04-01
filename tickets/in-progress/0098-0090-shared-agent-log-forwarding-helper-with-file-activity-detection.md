# 0090 Shared agent log-forwarding helper with file activity detection

**Area:** log-forwarding
**Priority:** medium

## Summary

Create a reusable proc in a new module `src/scriptorium/log_forwarding.nim` that all agent roles can call from their `onEvent` callbacks to forward meaningful stream events to orchestrator logs with a consistent format.

## Requirements

1. **Create `src/scriptorium/log_forwarding.nim`** with a public proc:
   ```nim
   proc forwardAgentEvent*(role: string, identifier: string, event: AgentStreamEvent)
   ```
   - `role`: agent role string (e.g. `"coding"`, `"manager"`, `"architect"`, `"review"`)
   - `identifier`: correlation ID (ticket ID, area ID, etc.)
   - `event`: the normalized `AgentStreamEvent` from `agent_runner.nim`

2. **Event handling logic:**
   - `agentEventTool`: Log at INFO level with prefix `{role}[{identifier}]: tool {event.text}`. Additionally, parse `event.text` to detect file activity (see below) and log a separate file activity line.
   - `agentEventStatus`: Log at INFO level with prefix `{role}[{identifier}]: status {event.text}`.
   - `agentEventHeartbeat`: Skip (do not log — these are high-frequency).
   - `agentEventReasoning`: Skip (too verbose for orchestrator logs).
   - `agentEventMessage`: Skip (final output, not a forwarding concern).

3. **File activity detection from tool events:**
   - Create a helper proc `extractFileActivity*(toolText: string): string` that examines tool event text and returns a file activity summary, or empty string if none detected.
   - Detect common tool patterns: `Read`, `Edit`, `Write`, `Bash` (with file-related args), `edit_file`, `read_file`, `write_file`, `create_file`.
   - For recognized file tools, extract the file path from the argument summary and log: `{role}[{identifier}]: file {read|write} {path}`.
   - Keep extraction best-effort — if the path cannot be parsed, log the tool call only (no file activity line).

4. **Use `logInfo` from `logging.nim`** for forwarded events (not `logDebug`), so they appear in orchestrator logs by default.

5. **Use `&` for format strings** per project conventions. Assign values to variables before interpolation.

6. **Imports:** Use bracket syntax, std/ first, then local modules (`./[agent_runner, logging]`).

7. **Doc comments (`##`)** on every proc.

## Acceptance Criteria

- Module compiles and exports `forwardAgentEvent` and `extractFileActivity`.
- Tool events produce an INFO log line with role and identifier prefix.
- File-related tool events produce an additional file activity log line.
- Status events produce an INFO log line.
- Heartbeat, reasoning, and message events are silently skipped.
- No new event types are invented — only existing `AgentStreamEventKind` values are used.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0098-0090-shared-agent-log-forwarding-helper-with-file-activity-detection

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 10
- reasoning: Single new module with straightforward pattern-matching logic on existing event types, no cross-module integration risk, one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0098/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0098/attempt-01.last_message.txt\n
### Agent Last Message
```text
Work complete. The new `src/scriptorium/log_forwarding.nim` module provides:

- **`forwardAgentEvent*(role, identifier, event)`** — logs tool and status events at INFO with `{role}[{identifier}]` prefix; skips heartbeat, reasoning, and message events.
- **`extractFileActivity*(toolText): string`** — parses tool event text to detect file reads/writes from Read, Edit, Write, Bash, read_file, write_file, create_file, and edit_file patterns.

All 23 unit tests pass and the PR has been submitted.
```

### Agent Stdout Tail
```text
Event*(role, identifier, event)`** — logs tool and status events at INFO with `{role}[{identifier}]` prefix; skips heartbeat, reasoning, and message events.\n- **`extractFileActivity*(toolText): string`** — parses tool event text to detect file reads/writes from Read, Edit, Write, Bash, read_file, write_file, create_file, and edit_file patterns.\n\nAll 23 unit tests pass and the PR has been submitted.","stop_reason":"end_turn","session_id":"c28012f4-a536-4f5d-a497-ef2e657552a8","total_cost_usd":0.36511999999999994,"usage":{"input_tokens":13,"cache_creation_input_tokens":22984,"cache_read_input_tokens":261160,"output_tokens":3633,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":22984,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":13,"outputTokens":3633,"cacheReadInputTokens":261160,"cacheCreationInputTokens":22984,"webSearchRequests":0,"costUSD":0.36511999999999994,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"cb2662e0-eca8-4150-bb5f-867893732bca"}
```

## Review
**Review:** changes requested
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 56s

**Review Feedback:** One correctness bug and one minor convention issue:

1. **Bug — operator precedence on line 62 of `log_forwarding.nim`:** The condition `t.len > 0 and t[0] != '-' and t.contains('/') or t.contains('.')` is missing parentheses. In Nim, `and` binds tighter than `or`, so this evaluates as `(t.len > 0 and t[0] != '-' and t.contains('/')) or t.contains('.')`. This means any token containing a `.` will match even if it starts with `-` (e.g., `-flag.txt` would be returned as a file path). Would you kindly add parentheses to make the intent explicit: `t.len > 0 and t[0] != '-' and (t.contains('/') or t.contains('.'))`.

2. **Convention — ungrouped `var` declarations (lines 15-16, 20):** Per AGENTS.md, `var` declarations should be grouped into a single block. Would you kindly group `toolName`, `rest`, and `splitIdx` into one `var` block.

**Review Reasoning:** Let me review the changes carefully.
Let me check the existing logging module for the `captureLogs`/`capturedLogs` mechanism and the agent_runner for `AgentStreamEvent`.
Now let me verify the operator precedence concern on line 62.


I've identified the issues. Let me submit my review.

**Key finding — operator precedence bug on line 62:**

```nim
if t.len > 0 and t[0] != '-' and t.contains('/') or t.contains('.'):
```

In Nim, `and` binds tighter than `or`, so this evaluates as:
```nim
(t.len > 0 and t[0] != '-' and t.contains('/')) or t.contains('.')
```

This means any token containing `.` will match regardless of the `t[0] != '-'` guard — a flag like `-flag.txt` would be returned as a file path, and a bare `.` or `..` would also match. The intended logic is clearly `t.len > 0 and t[0] != '-' and (t.contains('/') or t.contains('.'))`.

**Minor convention issue — ungrouped `var` declarations (lines 15-16, 20):**

```nim
var toolName = ""
var rest = ""
...
var splitIdx = -1
```

Per AGENTS.md, `var` declarations should be grouped into blocks.


Review submitted with **request_changes**. Two issues found:

1. **Operator precedence bug** (line 62): Missing parentheses around `t.contains('/') or t.contains('.')` causes the `or` to bypass the `-` flag guard and length check, allowing tokens like `-flag.txt` or bare `.` to incorrectly match as file paths.

2. **Minor convention**: `var` declarations on lines 15-16 and 20 should be grouped into a single `var` block per AGENTS.md rules.

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Single new module with straightforward case/pattern-matching on existing event types, but review flagged an operator precedence bug and a convention issue requiring a second attempt, adding ~2 min overhead.
