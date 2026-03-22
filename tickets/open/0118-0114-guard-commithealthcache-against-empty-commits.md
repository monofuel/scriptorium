# 0114 — Guard commitHealthCache against empty commits

**Area:** health-cache

## Problem

`commitHealthCache` in `src/scriptorium/health_checks.nim:53-56` unconditionally runs `gitRun(planPath, "commit", ...)`, which raises `IOError` if there are no staged changes. Other plan branch commit patterns in the codebase (e.g., `orchestrator.nim:166`) guard with `gitCheck(planPath, "diff", "--cached", "--quiet") != 0` before committing.

While the current call site always writes a new entry before committing, this is fragile — if the JSON serialization produces identical content (e.g., duplicate write of the same entry), the commit will fail.

## Task

In `src/scriptorium/health_checks.nim`, update `commitHealthCache` to check for staged changes before committing:

```nim
proc commitHealthCache*(planPath: string) =
  ## Stage and commit health/cache.json on the plan branch.
  gitRun(planPath, "add", HealthCacheRelPath)
  if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
    gitRun(planPath, "commit", "-m", HealthCacheCommitMessage)
