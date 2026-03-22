# 0077 — Rename architect log directories to nested structure

**Area:** log-persistence

## Problem

The current log directory names use flat paths:
- Spec logs: ticketId `plan-spec` → `.scriptorium/logs/plan-spec/`
- Area logs: `ArchitectAreasLogDirName = "architect-areas"` → `.scriptorium/logs/architect-areas/`

The area spec requires a nested structure:
- `.scriptorium/logs/architect/spec/`
- `.scriptorium/logs/architect/areas/`

## Task

In `src/scriptorium/architect_agent.nim`:

1. Change the `PlanSpecTicketId` constant (line 9) from `"plan-spec"` to `"architect" / "spec"` (or equivalently set the logRoot to include `architect` and ticketId to `spec`). The simplest approach: change the logRoot for spec runs to `repoPath / ManagedStateDirName / PlanLogDirName / "architect"` and set ticketId to `"spec"`. Update the `runPlanArchitectRequest` proc (line 43) accordingly — set `logRoot` to `repoPath / ManagedStateDirName / PlanLogDirName / "architect"` and `ticketId` to `"spec"`.

2. Change `ArchitectAreasLogDirName` (line 12) from `"architect-areas"` to `"architect" / "areas"` (i.e., nested). Update the `ArchitectAreasTicketId` (line 13) to just be an attempt identifier within the `architect/areas/` log dir. The simplest fix: set the logRoot for area runs (around line 468) to `planAgentLogRoot(repoPath, "architect" / "areas")` and keep ticketId as a simple identifier (e.g., the run attempt).

   Actually, looking at how `planAgentLogRoot` works — it returns `repoPath/.scriptorium/logs/<ticketId>`. So changing the call at line 468 from `planAgentLogRoot(repoPath, ArchitectAreasLogDirName)` to `planAgentLogRoot(repoPath, "architect" / "areas")` will produce `.scriptorium/logs/architect/areas/`. The ticketId `"architect-areas"` used as the log subdirectory name should then just be a run identifier. Review the harness log path logic to confirm the final structure is correct.

3. Update the constants to reflect the new names. Remove or rename `PlanSpecTicketId` and `ArchitectAreasLogDirName` / `ArchitectAreasTicketId` as appropriate.

## Verification

- `make test` passes
- Grep for old path names (`plan-spec`, `architect-areas`) to confirm they are fully removed
````

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0079-0077-rename-architect-log-directories-to-nested-structure

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 11
- reasoning: Single-file constant renaming and log path adjustments in architect_agent.nim with clear instructions, minimal integration risk, one attempt expected.
