# 0079-audit-agent-last-audited-commit

**Area:** audit-agent

## Description

Add infrastructure to track the "last audited commit" hash on the plan branch, so the orchestrator can detect when new merges have occurred since the last audit.

### Requirements

- Add a constant `AuditLastCommitPath` set to `"audit/.last-commit"` (relative to plan branch root) in `src/scriptorium/shared_state.nim` or a new `src/scriptorium/audit_agent.nim` file.
- Create a proc `readLastAuditedCommit*(planPath: string): string` that reads `audit/.last-commit` from the plan worktree, returning `""` if the file doesn't exist.
- Create a proc `writeLastAuditedCommit*(planPath: string, commitHash: string)` that writes the commit hash to `audit/.last-commit` in the plan worktree (creating the `audit/` directory if needed).
- Create a proc `auditShouldRun*(repoPath: string): bool` that:
  1. Opens a plan worktree (read-only, using `withPlanWorktree`).
  2. Reads the last audited commit.
  3. Compares it to the current default branch HEAD (using `defaultBranchHeadCommit` from `git_ops.nim`).
  4. Returns true if they differ (or if last audited commit is empty).
- Also detect spec changes: if the spec hash marker (`areas/.spec-hash`) has changed since the last audit, an audit should run. Store a `audit/.last-spec-hash` alongside the commit file.
- Add unit tests verifying:
  - Returns true when no `.last-commit` file exists.
  - Returns false when `.last-commit` matches current HEAD.
  - Returns true when they differ.

### Context

Follow the pattern used by `readSpecHashMarker`/`writeSpecHashMarker` in `src/scriptorium/architect_agent.nim`. Use `withPlanWorktree` / `withLockedPlanWorktree` from `git_ops.nim` for plan branch access.
