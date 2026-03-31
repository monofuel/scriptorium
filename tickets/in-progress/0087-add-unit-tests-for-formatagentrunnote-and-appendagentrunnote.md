# Add unit tests for formatAgentRunNote and appendAgentRunNote

**Area:** agent-execution

The `formatAgentRunNote` and `appendAgentRunNote` functions in `src/scriptorium/output_formatting.nim` produce the structured agent run notes appended to ticket markdown (backend, exit code, attempt, attempt count, timeout, log file, last-message file, last message tail, stdout tail). These are pure functions with zero test coverage anywhere in the test suite.

Create `tests/test_output_formatting.nim` with unit tests covering:

- `formatAgentRunNote` produces markdown with all required fields (model, backend, exit code, attempt, attempt count, timeout kind, log file, last message file).
- `formatAgentRunNote` includes last message preview section when `lastMessage` is non-empty.
- `formatAgentRunNote` includes stdout tail section when `stdout` is non-empty.
- `formatAgentRunNote` omits last message section when `lastMessage` is empty.
- `formatAgentRunNote` omits stdout tail section when `stdout` is empty.
- `formatAgentRunNote` truncates long stdout and lastMessage to `AgentStdoutPreviewChars` / `AgentMessagePreviewChars` respectively (uses `truncateTail` from `prompt_builders`).
- `appendAgentRunNote` appends the run note to existing ticket content with proper separation.
- `appendAgentRunNote` strips trailing whitespace from base content before appending.

Use `AgentRunResult` from `scriptorium/agent_runner` to construct test inputs. These are pure function tests — no mocks, no git, no external services.

Relevant source: `src/scriptorium/output_formatting.nim` lines 24–57.
Constants: `AgentMessagePreviewChars = 1200`, `AgentStdoutPreviewChars = 1200`.
Imports needed: `scriptorium/[agent_runner, output_formatting, prompt_builders]`.

Follow existing test patterns (see `tests/test_manager_agent.nim` for style).

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0087-add-unit-tests-for-formatagentrunnote-and-appendagentrunnote

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 10
- reasoning: Single new test file with pure function tests against well-defined interfaces, no mocks or external dependencies, straightforward pattern-matching from existing test style.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0087/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0087/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Created `tests/test_output_formatting.nim` with 9 passing unit tests covering all cases specified in the ticket: field presence, conditional sections, truncation, appending, and whitespace stripping.
```

### Agent Stdout Tail
```text
,"session_id":"382370e3-7bf8-4a3e-bedd-e566c6f688b2","uuid":"eedd6f9e-8e16-4ccb-8ab0-d0dda71ad4a8"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":59018,"duration_api_ms":57180,"num_turns":15,"result":"Done. Created `tests/test_output_formatting.nim` with 9 passing unit tests covering all cases specified in the ticket: field presence, conditional sections, truncation, appending, and whitespace stripping.","stop_reason":"end_turn","session_id":"382370e3-7bf8-4a3e-bedd-e566c6f688b2","total_cost_usd":0.3111815,"usage":{"input_tokens":15,"cache_creation_input_tokens":17824,"cache_read_input_tokens":262013,"output_tokens":2748,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":17824,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":15,"outputTokens":2748,"cacheReadInputTokens":262013,"cacheCreationInputTokens":17824,"webSearchRequests":0,"costUSD":0.3111815,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"ef699448-ddd5-42f1-be40-991f2cc2636c"}
```
