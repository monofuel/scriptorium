```markdown
# 0120 — Rename architect log directories to consistent structure

**Area:** log-persistence
**File:** `tickets/0120-rename-architect-log-dirs.md`

## Problem

Architect logs use inconsistent directory names:
- Spec logs go to `.scriptorium/logs/` (via `PlanLogDirName = "logs"`) — effectively `.scriptorium/logs/plan-spec/`
- Area generation logs go to `.scriptorium/logs/architect-areas/`

The target structure is:
- `.scriptorium/logs/architect/spec/`
- `.scriptorium/logs/architect/areas/`

## Task

Update the architect agent log path constants and `planAgentLogRoot` helper so logs land under `.scriptorium/logs/architect/spec/` and `.scriptorium/logs/architect/areas/`.

### Details

- In `src/scriptorium/architect_agent.nim` (around lines 9-14):
  - The spec run currently uses `logRoot: repoPath / ManagedStateDirName / PlanLogDirName` (line 52) where `PlanLogDirName = "logs"`. Change the spec logRoot to `repoPath / ".scriptorium" / "logs" / "architect" / "spec"`.
  - The areas run uses `logRoot: planAgentLogRoot(repoPath, ArchitectAreasLogDirName)` (line 468) where `ArchitectAreasLogDirName = "architect-areas"`. Change this to produce `.scriptorium/logs/architect/areas/`.
- Update or remove the `planAgentLogRoot` helper (lines 60-66) if it no longer serves a useful purpose, or adjust it to produce paths under `.scriptorium/logs/architect/`.
- The manager agent in `src/scriptorium/manager_agent.nim` also uses `planAgentLogRoot`. Its logs currently go to `.scriptorium/logs/manager/<areaId>/` which is already correct per the target structure. Make sure manager log paths are not broken by changes to `planAgentLogRoot`. If `planAgentLogRoot` is being removed or significantly changed, update the manager's logRoot construction to use a direct path like `repoPath / ".scriptorium" / "logs" / "manager" / areaId`.
- Update any tests that reference the old log directory names.

### Verification

- `make test` passes.
- Spec agent logRoot resolves to `.scriptorium/logs/architect/spec/`.
- Areas agent logRoot resolves to `.scriptorium/logs/architect/areas/`.
- Manager agent logRoot still resolves to `.scriptorium/logs/manager/<areaId>/`.
