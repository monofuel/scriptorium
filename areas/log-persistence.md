# Per-Role Log Persistence

Agent logs persist in the repo root under `.scriptorium/logs/` organized by role, not in worktrees that are cleaned up after merge.

## Scope

- Log directory structure:
  ```
  .scriptorium/logs/
    orchestrator/              # run_*.log (existing, unchanged)
    architect/
      spec/                    # architect spec runs
      areas/                   # architect area generation
    manager/
      <areaId>/                # per-area manager runs
    coder/
      <ticketId>/              # coding agent execution
        attempt-01.jsonl
        attempt-02.jsonl
    prediction/
      <ticketId>/              # difficulty predictions
    review/
      <ticketId>/              # review agent runs
        attempt-01.jsonl
    audit/                     # audit agent reports
  ```
- Review agent: set `logRoot` in `AgentRunRequest` to `repoPath/.scriptorium/logs/review` so JSONL logs persist after worktree cleanup.
- Coding agent: set `logRoot` to `repoPath/.scriptorium/logs/coder` so execution logs persist after worktree cleanup.
- Rename existing log directories to match the consistent per-role structure: `plan-spec/` -> `architect/spec/`, `architect-areas/` -> `architect/areas/`, `<ticketId>-prediction/` -> `prediction/<ticketId>/`.

## Spec References

- Section 21: Per-Role Log Persistence.
