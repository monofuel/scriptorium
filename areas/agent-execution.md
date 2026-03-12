# Architect, Manager, And Coding Agent Execution

Covers agent-driven area generation, ticket generation, coding agent runs, and per-ticket metrics.

## Scope

- Architect area generation (continuous, content-hash driven):
  - `spec.md` must be runnable.
  - Orchestrator stores SHA-1 hash of `spec.md` in `areas/.spec-hash`.
  - First run (no `.spec-hash` marker): generate areas and write the marker.
  - Subsequent ticks: re-run only when current `spec.md` hash differs from stored hash.
  - After generation, orchestrator updates `areas/.spec-hash` and commits the marker separately.
  - Migration: if areas exist but no `.spec-hash` marker, write the marker from current spec without re-running.
  - Writes area files directly under `areas/`.
- Manager ticket generation (continuous, content-hash driven):
  - Orchestrator stores per-area SHA-1 hashes in `tickets/.area-hashes` (tab/colon-separated `area-id:hash`, one per line, sorted).
  - Areas with open or in-progress tickets are always suppressed.
  - When `tickets/.area-hashes` exists, areas whose content hash differs from stored hash are eligible for re-ticketing, even if previous tickets for that area are done.
  - When `tickets/.area-hashes` does not exist (legacy fallback), areas with any ticket in any state are suppressed.
  - After ticket generation, orchestrator computes and writes hashes for all current areas and commits the hash file separately.
  - Batched execution: all eligible areas in a single agent prompt and session.
  - Writes constrained by write-prefix allowlist to `tickets/open/`.
  - Must preserve dirty state of the main repository outside the plan worktree.
  - Ticket filenames assigned by the orchestrator, not by agent prompt output.
- Coding agent execution:
  - Runs in the assigned ticket worktree.
  - Prompt includes ticket path, ticket content, repo path, and worktree path.
  - Appends structured agent run notes to ticket markdown:
    - Backend, exit code, attempt, attempt count, timeout, log file, last-message file, last message tail, stdout tail.
  - Enqueues merge request metadata only when the coding agent calls the MCP `submit_pr` tool.
  - Merge-queue enqueueing uses MCP tool state, not stdout scanning.
- Per-ticket metrics in agent run notes (V3):
  - Structured metrics persisted in ticket markdown alongside existing agent run notes.
  - Required fields: `wall_time_seconds`, `coding_wall_seconds`, `test_wall_seconds`, `attempt_count`, `outcome`, `failure_reason`, `model`, `stdout_bytes`.
  - Every completed or reopened ticket must have all listed fields.
  - Detail in ticket-metrics area.

## Spec References

- Section 5: Architect, Manager, And Coding Agent Execution.
- Section 15: Per-Ticket Metrics In Agent Run Notes (V3, detail in ticket-metrics area).
