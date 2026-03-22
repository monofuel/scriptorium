# Review-driven retry: restart coding agent instead of reopening ticket

**Area:** agent-execution

When the review agent requests changes, the spec says the ticket should stay in-progress and a new coding agent session should start with review feedback in the same worktree/branch. Currently, the code moves the ticket back to `open/`, losing the worktree association and requiring full re-assignment.

## Current State

In `src/scriptorium/merge_queue.nim:processMergeQueue` (around line 357-375), when `reviewDecision.action == "request_changes"`:
- The ticket is moved from `in-progress/` to `open/`.
- The worktree and branch are abandoned.
- No coding agent is restarted with review feedback.

## Required Changes

1. In `src/scriptorium/merge_queue.nim:processMergeQueue`, when review requests changes:
   - Do NOT move the ticket to `open/`. Keep it in `in-progress/`.
   - Append the review feedback to the ticket markdown (this already happens via the review note).
   - Return a signal indicating a review retry is needed. Add a new field to the return or use a structured result type.

2. Create a `buildReviewRetryCodingPrompt` proc in `src/scriptorium/prompt_builders.nim` that:
   - Includes the original ticket content.
   - Includes the review feedback with a section header like "## Review Feedback".
   - Directs the agent to address the feedback and call `submit_pr` when done.
   - Add a corresponding `review_retry.md` prompt template in `src/scriptorium/prompts/`.

3. In the orchestrator or merge queue caller, when a review retry is signaled:
   - Build the review retry prompt with the original ticket content and review feedback.
   - Start a new coding agent session in the existing worktree using `executeAssignedTicket` (or equivalent).
   - Review-driven retries must count toward the ticket's total `attempt_count`.
   - If max attempts are exhausted, then reopen the ticket.

4. For the parallel execution path (`maxAgents > 1`), the retry should be handled by enqueuing a new coding agent slot for the same ticket/worktree/branch, since `processMergeQueue` runs on the main thread and cannot block for agent execution.

## Verification

- `make test` passes.
- When review requests changes, the ticket stays in-progress and a new coding agent run begins with review context.
