# Stall Detection And Automatic Continuation

Detect coding agent stalls (exit without `submit_pr`) and retry with test-aware continuation prompts.

## Scope

- Stall definition: coding agent turn completes (process exits) without calling the `submit_pr` MCP tool.
- On stall, run `make test` in the agent's worktree and capture the result.
  - If tests fail: continuation prompt includes test failure output and a directive to fix tests.
  - If tests pass: continuation prompt includes a note that tests pass and a directive to continue.
- Retry with a continuation prompt including the original ticket content.
- Retries use existing bounded retry mechanism (`maxAttempts` in `AgentRunRequest`).
- Each retry is logged with attempt number and ticket ID.
- Continuation prompt is distinct from initial prompt — indicates this is a retry after a stall.

## Spec References

- Section 7: Coding Agent Execution (stall detection and log forwarding).
