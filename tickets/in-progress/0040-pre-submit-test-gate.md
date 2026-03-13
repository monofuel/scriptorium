# Pre-Submit Test Gate In submit_pr MCP Tool

**Area:** agent-execution

## Problem

The `submit_pr` MCP tool handler in `orchestrator.nim` (line ~2566) unconditionally records the submit summary and returns "Merge request enqueued." without running any tests. The V4 spec (§20) requires `submit_pr` to run `make test` in the agent's worktree before accepting the submission.

## Current State

The handler is:
```nim
let submitPrHandler: ToolHandler = proc(arguments: JsonNode): JsonNode {.gcsafe.} =
  let summary = arguments["summary"].getStr()
  recordSubmitPrSummary(summary)
  %*"Merge request enqueued."
```

No tests are run. The merge queue later runs `make test` and `make integration-test`, but by then the coding agent has already exited.

## Requirements

- The `submit_pr` MCP tool handler must run `make test` in the coding agent's worktree before accepting the submission.
- The handler needs access to the current ticket's worktree path. This may require storing the active worktree path in a shared variable (similar to `submitPrSummaryBuffer`) or passing it through the handler closure.
- If `make test` fails:
  - Return an error JSON response to the agent with test failure output (truncated if long).
  - Direct the agent to fix failing tests and call `submit_pr` again.
  - Do NOT call `recordSubmitPrSummary()` — the merge request must NOT be enqueued.
- If `make test` passes:
  - Call `recordSubmitPrSummary()` and return success response as before.
- Log: `ticket <id>: submit_pr pre-check: <PASS|FAIL> (exit=<code>, wall=<duration>)`.
- The handler blocks while tests run — this is expected and counts against the agent's hard timeout.
- Only `make test` is run, not `make integration-test` (integration tests remain a merge queue concern).

## Implementation Notes

- Add a thread-safe shared variable for the active ticket worktree path (set when a ticket is assigned, cleared after execution).
- Add a thread-safe shared variable for the active ticket ID (for logging).
- Use `runQualityTarget("test", worktreePath)` or equivalent to run `make test`.
- Truncate test output in error responses to avoid overwhelming the agent (e.g., last 2000 chars).
- Update existing tests that verify `submit_pr` behavior.

## Acceptance Criteria

- `submit_pr` runs `make test` before enqueuing.
- Failing tests return error to agent without enqueuing.
- Passing tests enqueue normally.
- Pre-check logged with ticket ID, pass/fail, exit code, and wall time.
- Unit tests cover both pass and fail paths.

## Spec References

- Section 20: Pre-Submit Test Gate (V4).

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0040-pre-submit-test-gate
