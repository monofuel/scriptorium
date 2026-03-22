```markdown
# 0121 — Rename prediction log directories to consistent structure

**Area:** log-persistence
**File:** `tickets/0121-rename-prediction-log-dirs.md`

## Problem

Prediction agent logs currently use `ticketId: ticketId & "-prediction"` (in `src/scriptorium/coding_agent.nim` around line 84) with no explicit `logRoot`, producing paths like `.scriptorium/logs/<ticketId>-prediction/`. The target structure is `.scriptorium/logs/prediction/<ticketId>/`.

## Task

Set an explicit `logRoot` for the prediction agent and adjust the ticketId so logs land under `.scriptorium/logs/prediction/<ticketId>/`.

### Details

- In `src/scriptorium/coding_agent.nim`, find the prediction `AgentRunRequest` (around lines 78-92).
- Add `logRoot: repoPath / ".scriptorium" / "logs" / "prediction"` to the request.
- Change `ticketId` from `ticketId & "-prediction"` back to just `ticketId` so the log path becomes `.scriptorium/logs/prediction/<ticketId>/attempt-01.jsonl`.
- The `repoPath` should already be in scope for prediction since it runs against `workingDir: repoPath` (not a worktree). Confirm this.
- Update any tests that reference the old `<ticketId>-prediction` pattern.

### Verification

- `make test` passes.
- Prediction agent logRoot resolves to `.scriptorium/logs/prediction/<ticketId>/`.
