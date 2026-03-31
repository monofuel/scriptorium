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
