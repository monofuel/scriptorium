# Review Agent Live Integration Test

**Area:** review-agent

## Problem

V7 §30 requires a live integration test for the review agent, similar to `integration_mcp_submit_pr_live.nim`. No integration test currently exists for the review agent flow.

## Requirements

### Live integration test
- Create `tests/integration_review_agent_live.nim`.
- Run the review agent with a real model (using the reviewer config from `scriptorium.json`).
- Provide a real diff against a real branch (not synthetic input).
- Start the MCP server so the review agent can call `submit_review`.
- Verify the review agent calls `submit_review` with either `approve` or `request_changes`.
- Verify the review decision is consumable via `consumeReviewDecision`.

### Test structure
- Follow patterns from `integration_mcp_submit_pr_live.nim`.
- Test requires API credentials and a running model.
- Test runs only in `make integration-test`, not `make test`.
- Test must clean up worktrees and branches after completion.

## Acceptance Criteria

- `tests/integration_review_agent_live.nim` exists and follows integration test conventions.
- Test runs a real review agent session with a real model and real diff.
- Test verifies `submit_review` was called.
- `make integration-test` includes the new test.
- No mocks or fakes used.
