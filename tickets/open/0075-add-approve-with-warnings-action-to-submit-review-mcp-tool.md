# Add approve_with_warnings action to submit_review MCP tool

**Area:** agent-execution

The spec section 9 defines three review actions: `approve`, `approve_with_warnings`, and `request_changes`. Currently, the `submit_review` MCP tool only accepts `approve` and `request_changes`, rejecting `approve_with_warnings`.

## Current State

In `src/scriptorium/mcp_server.nim`, the `submit_review` tool schema has `"enum": ["approve", "request_changes"]` and the handler rejects any action other than those two.

In `src/scriptorium/merge_queue.nim:runReviewAgent`, the result handling checks `result.action == "approve"` and `result.action == "request_changes"` — `approve_with_warnings` would fall through to the stall default.

## Required Changes

1. In `src/scriptorium/mcp_server.nim`, update the `submit_review` tool:
   - Add `"approve_with_warnings"` to the enum array in `inputSchema`.
   - Update the handler validation to accept `approve_with_warnings` as a valid action.

2. In `src/scriptorium/merge_queue.nim:runReviewAgent`:
   - Add an `elif result.action == "approve_with_warnings"` branch after the `approve` check.
   - Log at INFO level: `"ticket {ticketId}: review approved with warnings"`.
   - Include any feedback (warnings) in the review note appended to the ticket.
   - Treat it as approval for merge queue progression (same as `approve`).

3. Update the review note formatting for `approve_with_warnings` to include `**Review:** approved with warnings` and list the warnings from the feedback field.

## Verification

- `make test` passes.
- An `approve_with_warnings` action is accepted by the MCP tool and results in merge proceeding with warnings logged.
