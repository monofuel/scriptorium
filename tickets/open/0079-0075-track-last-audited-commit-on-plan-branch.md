<!-- file: tickets/open/0075-audit-state-tracking.md -->
# 0075 — Track last audited commit on plan branch

**Area:** audit-agent

Add persistent state tracking for the audit agent so the orchestrator knows when an audit is needed.

## Details

Create audit state tracking in `src/scriptorium/shared_state.nim` (or a new `src/scriptorium/audit_agent.nim` file if it keeps shared_state cleaner):

1. Define an `AuditState` object with fields:
   - `lastAuditedCommit: string` — the default branch HEAD at the time of the last audit
   - `lastAuditTimestamp: string` — ISO timestamp of the last audit

2. Define a constant for the state file path on the plan branch: `.scriptorium/audit-state.json`.

3. Add a `loadAuditState(repoPath: string): AuditState` proc that reads the state file from the plan branch (using `git show` like other plan branch reads). Return an empty/default state if the file doesn't exist.

4. Add a `saveAuditState(repoPath: string, state: AuditState)` proc that writes the state file to the plan branch using `withLockedPlanWorktree` (follow the existing plan branch write patterns in `git_ops.nim`).

5. Add a `needsAudit(repoPath: string): bool` proc that:
   - Loads the audit state
   - Gets current default branch HEAD
   - Returns `true` if HEAD differs from `lastAuditedCommit`

Use `jsony` for JSON serialization (existing project dependency).

## Verification

- `make test` passes.
- Unit test: `needsAudit` returns true when HEAD differs from stored commit, false when same.
