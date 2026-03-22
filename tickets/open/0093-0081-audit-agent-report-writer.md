# 0081-audit-agent-report-writer

**Area:** audit-agent

**Depends:** 0080

## Description

Implement the report writer that saves audit results as timestamped markdown files to `.scriptorium/logs/audit/`.

### Requirements

- Add a proc `writeAuditReport*(repoPath: string, reportContent: string): string` (in `src/scriptorium/audit_agent.nim` or a new helper) that:
  1. Creates the directory `.scriptorium/logs/audit/` under `repoPath` if it doesn't exist.
  2. Generates a filename using a UTC timestamp, e.g., `2026-03-22T14-30-00Z.md`.
  3. Writes the report content to that file.
  4. Returns the full path to the written file.
- The report should include a header with metadata:
  - Timestamp
  - Audited commit hash
  - Previous audited commit hash (or "initial" if first audit)
- After writing the report, update the last audited commit and spec hash on the plan branch using `withLockedPlanWorktree`, `writeLastAuditedCommit`, git add, and commit with message `"scriptorium: update audit marker"`.
- Add a unit test that verifies the report file is created with the expected path pattern and contains the report content.

### Context

Follow the logging pattern in `src/scriptorium/logging.nim` for timestamp formatting (`formatFileTimestamp` style). The `.scriptorium/` directory is already gitignored (see `ensureScriptoriumIgnored` in `git_ops.nim`), so audit reports stored there won't pollute the repo.
