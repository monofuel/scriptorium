```markdown
# 0118 — Set logRoot for review agent

**Area:** log-persistence
**File:** `tickets/0118-review-agent-log-root.md`

## Problem

The review agent in `src/scriptorium/merge_queue.nim` does not set `logRoot` in its `AgentRunRequest` (around line 213). Logs default to `<worktree>/.scriptorium/logs/<ticketId>/`, and are deleted when the worktree is cleaned up after merge.

## Task

Set `logRoot` on the review agent's `AgentRunRequest` to `repoPath / ".scriptorium" / "logs" / "review"` so JSONL logs persist in the repo root after worktree cleanup.

### Details

- In `src/scriptorium/merge_queue.nim`, find the `AgentRunRequest` construction for the review agent (around lines 213-229).
- Add `logRoot: repoPath / ".scriptorium" / "logs" / "review"` to the request. The `repoPath` variable is already available in scope — trace through the call chain to confirm. If only `item.worktree` is available, you'll need to thread `repoPath` through.
- The harness code in `harness_codex.nim`, `harness_claude_code.nim`, and `harness_typoi.nim` already handles `logRoot` — if non-empty, it uses it as the base; otherwise it falls back to `workingDir / ".scriptorium/logs"`. No harness changes needed.
- The resulting log path will be `.scriptorium/logs/review/<ticketId>/attempt-01.jsonl`.

### Verification

- `make test` passes.
- Confirm the review agent request construction includes `logRoot` pointing to the repo-root log directory.
