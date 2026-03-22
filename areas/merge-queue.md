# Merge Queue Safety Contract

Covers the single-flight merge queue, quality gates, and ticket state transitions on merge.

## Scope

- Single-flight: at most one pending item processed per pass.
- Queue processing flow:
  1. Ensure queue metadata exists.
  2. Set `queue/merge/active.md` to the currently processed pending item.
  3. Merge `master` into the ticket branch worktree.
  4. Run required quality targets in the ticket worktree: `make test`, `make integration-test`.
  5. On success: fast-forward merge ticket branch into `master`, append merge success note, move ticket `in-progress -> done`.
  6. On failure: append merge failure note, move ticket `in-progress -> open`.
- Queue metadata cleaned up after success, failure, or stale-item cleanup.
- Stale queue items (ticket already moved to `open` or `done`) removed with active metadata cleared.
- Merge success and failure notes include submit summary and relevant output tails.
- Stale managed worktrees for non-active tickets removable by cleanup.
- Pending merge queue items processed in submission order (FIFO by queue item ID).
- Pre-submit test gate:
  - The `submit_pr` MCP tool must run `make test` in the agent's worktree before accepting a submission.
  - If tests fail: return error response to the agent with test failure output, directing the agent to fix failing tests and call `submit_pr` again. Merge request NOT enqueued.
  - If tests pass: record submit summary and return success response. Merge request enqueued.
  - Agent remains running during test execution — `submit_pr` blocks until tests complete.
- Review agent integration:
  - Every pending merge queue item goes through review agent before merging (see review-agent area).
  - Approved reviews proceed to existing quality gate flow.
  - Change requests remove the queue item and restart the coding agent with review feedback.
- Multiple agents may call `submit_pr` independently, creating multiple pending merge queue entries.
- Failed merges do not affect other in-flight agents or pending queue items.
- After successful merge changes `master`, existing merge queue logic handles merging `master` into ticket branches before quality gates.

## Spec References

- Section 10: Merge Queue Safety Contract.
- Section 8: Pre-Submit Test Gate.
- Section 9: Review Agent (detail in review-agent area).
- Section 11: Parallel Ticket Assignment And Concurrency (merge queue ordering with parallel agents).
