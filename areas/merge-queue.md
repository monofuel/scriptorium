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
- Legacy repo-local worktrees under `.scriptorium/worktrees` removable by cleanup and assignment flows.
- Pre-submit test gate (V4, §20):
  - The `submit_pr` MCP tool must run `make test` in the agent's worktree before accepting a submission.
  - If tests fail: return error response to the agent with test failure output (truncated if long), directing the agent to fix failing tests and call `submit_pr` again. Merge request NOT enqueued.
  - If tests pass: record submit summary and return success response. Merge request enqueued as before.
  - Test run logged: `ticket <id>: submit_pr pre-check: <PASS|FAIL> (exit=<code>, wall=<duration>)`.
  - Agent remains running during test execution — `submit_pr` blocks until tests complete.
  - Replaces previous behavior where `submit_pr` unconditionally accepted submissions.
- Review agent integration (V4, §21):
  - Every pending merge queue item goes through review agent before merging (see review-agent area).
  - Approved reviews proceed to existing quality gate flow.
  - Change requests remove the queue item and restart the coding agent with review feedback.

- Merge queue ordering with parallel agents (V5, §25):
  - Multiple agents may call `submit_pr` independently, creating multiple pending merge queue entries.
  - Pending items processed in submission order (FIFO by queue item ID).
  - Failed merges do not affect other in-flight agents or pending queue items.
  - After successful merge changes `master`, existing merge queue logic handles merging `master` into ticket branches before quality gates.
  - Detail in parallel-execution area.

## V4 Known Limitations

- Pre-submit test gate runs `make test` only, not `make integration-test` — integration tests remain a merge queue concern.
- The `submit_pr` MCP handler blocks the coding agent process while tests run, which counts against the agent's hard timeout.

## V5 Known Limitations

- Merge queue remains single-flight even with parallel agents — serialization point may bottleneck at high concurrency.

## Spec References

- Section 7: Merge Queue Safety Contract.
- Section 20: Pre-Submit Test Gate (V4).
- Section 21: Review Agent (V4, detail in review-agent area).
- Section 25: Merge Queue Ordering With Parallel Agents (V5, detail in parallel-execution area).
