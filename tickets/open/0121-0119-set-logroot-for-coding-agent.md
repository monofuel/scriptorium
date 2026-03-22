```markdown
# 0119 — Set logRoot for coding agent

**Area:** log-persistence
**File:** `tickets/0119-coding-agent-log-root.md`

## Problem

The coding agent in `src/scriptorium/coding_agent.nim` does not set `logRoot` in its `AgentRunRequest` (around line 176). Logs default to `<worktree>/.scriptorium/logs/<ticketId>/`, and are deleted when the worktree is cleaned up after merge.

## Task

Set `logRoot` on the coding agent's `AgentRunRequest` to `repoPath / ".scriptorium" / "logs" / "coder"` so JSONL logs persist in the repo root after worktree cleanup.

### Details

- In `src/scriptorium/coding_agent.nim`, find the `AgentRunRequest` construction for the coding agent (around lines 126-200).
- Add `logRoot: repoPath / ".scriptorium" / "logs" / "coder"` to the request. The `repoPath` should be available in scope — trace through the call chain (e.g. from `executeTicket` or similar). If not directly available, thread it through from the caller.
- The harness layer already respects `logRoot` when non-empty. No harness changes needed.
- The resulting log path will be `.scriptorium/logs/coder/<ticketId>/attempt-01.jsonl`.

### Verification

- `make test` passes.
- Confirm the coding agent request construction includes `logRoot` pointing to the repo-root log directory.
