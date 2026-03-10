# Include argument summary in tool event text

Both harnesses currently emit tool events with only the tool name (e.g., `Bash`, `edit_file`). The spec (Section 10) requires tool call logs to include an argument summary so operators can see what file is being acted on — e.g., `"agent: tool edit_file src/foo.nim"`.

## Current behavior

Claude Code harness (`buildClaudeCodeStreamEvent` in `harness_claude_code.nim:260`):
```nim
of "tool_use":
  let toolName = firstBlock.getOrDefault("name").getStr("")
  # only extracts name, ignores input
```

The `input` field is present in the JSON (e.g., `{"type":"tool_use","name":"Bash","id":"toolu_123","input":{"command":"ls"}}`) but is not used.

Codex harness (`buildCodexStreamEventFromEnvelope` in `harness_codex.nim:423`): uses `resolveCodexToolName` and `resolveCodexToolState` but does not extract file path arguments.

## Task

### Claude Code harness

In `buildClaudeCodeStreamEvent`, when handling `tool_use` blocks, extract a short argument summary from the `input` field and append it to the tool event text. The summary should be the first relevant argument value — typically a file path.

Extraction rules:
- Look for common file-path keys in `input`: `file_path`, `path`, `filename`, `file`, `command`.
- If found, append the value to the tool name: `"Edit file_path=/src/foo.nim"` or simply `"Edit src/foo.nim"`.
- If `input` has a `command` key (for Bash tool), append a truncated command summary (first 80 chars).
- If no recognized key is found, emit just the tool name as today.
- Keep the summary short — do not dump the entire input object.

### Codex harness

Apply the same logic in `buildCodexStreamEventFromEnvelope`. The codex envelope structure has nested `tool`, `data`, and `event` objects — extract argument summary from whichever contains the tool arguments.

## Files

- `src/scriptorium/harness_claude_code.nim:260` — `tool_use` branch in `buildClaudeCodeStreamEvent`
- `src/scriptorium/harness_codex.nim:423` — `buildCodexStreamEventFromEnvelope`
- `tests/test_harness_claude_code.nim` — add tests for argument summary extraction
- `tests/test_harness_codex.nim` — add tests for argument summary extraction

## Acceptance criteria

- Claude Code tool events include file path or command summary when available in `input`.
- Codex tool events include argument summary when available.
- Tool events without recognized argument keys continue to emit just the tool name.
- Argument summaries are truncated to a reasonable length (80 chars max).
- Existing harness tests continue to pass.
- `make test` passes with new assertion coverage.

**Area:** log-forwarding

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0020-tool-event-argument-summary

## Agent Run
- Model: claude-sonnet-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 2\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0020-tool-event-argument-summary/.scriptorium/logs/0020/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0020-tool-event-argument-summary/.scriptorium/logs/0020/attempt-02.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` MCP tool was called successfully. The merge request has been enqueued with the summary:

**"Extract file path and command argument summaries from tool_use input fields and append to tool event text in both Claude Code and Codex harnesses. Adds tests for the new extraction logic."**

The work from the previous attempt was already committed (commit `8139084`), which includes:
- `src/scriptorium/harness_claude_code.nim` — extracts file path/command from `input` fields in `tool_use` events
- `src/scriptorium/harness_codex.nim` — same logic for Codex harness
- `tests/test_harness_claude_code.nim` — new test coverage
- `tests/test_harness_codex.nim` — new test coverage
```

### Agent Stdout Tail
```text
w extraction logic.\"**\n\nThe work from the previous attempt was already committed (commit `8139084`), which includes:\n- `src/scriptorium/harness_claude_code.nim` — extracts file path/command from `input` fields in `tool_use` events\n- `src/scriptorium/harness_codex.nim` — same logic for Codex harness\n- `tests/test_harness_claude_code.nim` — new test coverage\n- `tests/test_harness_codex.nim` — new test coverage","stop_reason":"end_turn","session_id":"a9a5ba9b-ff97-4ce2-9277-46645657a420","total_cost_usd":1.007853,"usage":{"input_tokens":61,"cache_creation_input_tokens":23366,"cache_read_input_tokens":1359971,"output_tokens":7261,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":23366,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-sonnet-4-6":{"inputTokens":61,"outputTokens":7261,"cacheReadInputTokens":1359971,"cacheCreationInputTokens":23366,"webSearchRequests":0,"costUSD":1.007853,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"37bd6ff2-c7ee-44ec-b558-306732261765"}
```
