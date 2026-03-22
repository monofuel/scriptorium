<!-- ticket: 0074-approve-with-warnings-action.md -->
# Add `approve_with_warnings` action to review agent

**Area:** review-agent
**Difficulty:** medium

## Problem

The `submit_review` MCP tool in `src/scriptorium/mcp_server.nim` only supports two actions: `approve` and `request_changes`. The spec (Section 9) and area definition require a third action: `approve_with_warnings`, which accepts the changes but logs warnings for minor style issues.

## Requirements

1. **MCP tool update** (`src/scriptorium/mcp_server.nim`):
   - Add `"approve_with_warnings"` to the `enum` array in the `submit_review` tool's `inputSchema`.
   - Update the validation in `submitReviewHandler` to accept `approve_with_warnings` as a valid action.
   - When `action` is `approve_with_warnings`, `feedback` should be accepted (warnings text) but not required.

2. **Merge queue handling** (`src/scriptorium/merge_queue.nim`):
   - In `runReviewAgent`, handle `approve_with_warnings` as a successful review (merge proceeds).
   - Log at INFO level: `ticket <id>: review approved with warnings`.
   - Append a structured review note to the ticket markdown that includes the warnings text from `feedback`. Use a format like:

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0080-add-approve-with-warnings-action-to-review-agent

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Two-file change adding a new enum variant and a simple branch in the review handler — the logic mirrors existing approve/request_changes paths with no complex integration risk.
