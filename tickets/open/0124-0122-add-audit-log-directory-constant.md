```markdown
# 0122 — Add audit log directory constant

**Area:** log-persistence
**File:** `tickets/0122-audit-log-directory.md`

## Problem

The target log structure includes `.scriptorium/logs/audit/` for audit agent reports, but there is no log path wiring for the audit agent yet.

## Task

Add the audit log directory path so the audit agent writes logs to `.scriptorium/logs/audit/`.

### Details

- Find where the audit agent is launched (search for "audit" in `src/scriptorium/`). If an `AgentRunRequest` is constructed for audit runs, set `logRoot: repoPath / ".scriptorium" / "logs" / "audit"`.
- If the audit agent doesn't exist yet or doesn't use `AgentRunRequest`, add a TODO comment at the appropriate location noting that audit logs should go to `.scriptorium/logs/audit/` when the agent is implemented.
- Do not create the audit agent itself — just ensure the log path is wired or documented.

### Verification

- `make test` passes.
- If audit agent exists: its `AgentRunRequest` includes the correct `logRoot`.
- If audit agent doesn't exist yet: a TODO comment is placed at the most logical location.
