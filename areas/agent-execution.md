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
  - Areas with open or in-progress tickets are always suppressed (blocks concurrent work on the same area).
  - When `tickets/.area-hashes` exists, areas whose content hash differs from stored hash are eligible for re-ticketing, even if previous tickets for that area are done.
  - When `tickets/.area-hashes` does not exist (legacy fallback), areas with any ticket in any state are suppressed.
  - After ticket generation, orchestrator computes and writes hashes for all current areas and commits the hash file separately.
  - Per-area concurrent execution (V13, §29): each eligible area spawns an independent manager agent using `manager_tickets.md`. Replaces the retired batched single-prompt model (V13, §32).
  - Manager agents generate ticket content in memory — only the orchestrator main thread writes to the plan worktree.
  - Manager writes constrained by write-prefix allowlist to `tickets/open/`.
  - Must preserve dirty state of the main repository outside the plan worktree.
  - Ticket filenames assigned by the orchestrator, not by agent prompt output.
  - Managers share the `maxAgents` slot pool with coding agents via `AgentRole` enum (V13, §28, detail in parallel-execution area).
- Coding agent execution:
  - Runs in the assigned ticket worktree.
  - Prompt includes ticket path, ticket content, repo path, and worktree path.
  - Appends structured agent run notes to ticket markdown:
    - Backend, exit code, attempt, attempt count, timeout, log file, last-message file, last message tail, stdout tail.
  - Enqueues merge request metadata only when the coding agent calls the MCP `submit_pr` tool.
  - Merge-queue enqueueing uses MCP tool state, not stdout scanning.
  - Pre-submit test gate (V4, §20): `submit_pr` runs `make test` before enqueuing; on failure returns error to agent with test output; on success enqueues normally (detail in merge-queue area).
- Review agent execution (V4, §21):
  - New agent role under `agents.reviewer` in `scriptorium.json`.
  - Runs in the ticket's worktree when a pending merge queue item is processed.
  - Prompt includes ticket content, diff against `master`, area content, and submit summary.
  - Has access to `submit_review` MCP tool with `approve` and `request_changes` actions.
  - Approved: merge proceeds. Changes requested: coding agent restarted with review feedback.
  - Stall defaults to approval. Detail in review-agent area.
- Per-ticket metrics in agent run notes (V3):
  - Structured metrics persisted in ticket markdown alongside existing agent run notes.
  - Required fields: `wall_time_seconds`, `coding_wall_seconds`, `test_wall_seconds`, `attempt_count`, `outcome`, `failure_reason`, `model`, `stdout_bytes`.
  - Every completed or reopened ticket must have all listed fields.
  - Detail in ticket-metrics area.

- Concurrent agent execution (V5, §24):
  - Multiple coding agents run in parallel, each in its own worktree, fully isolated.
  - Agent lifecycle (start, stall detection, continuation, submit_pr) applies independently per agent.
  - Detail in parallel-execution area.

## Spec References

- Section 5: Architect, Manager, And Coding Agent Execution.
- Section 15: Per-Ticket Metrics In Agent Run Notes (V3, detail in ticket-metrics area).
- Section 20: Pre-Submit Test Gate (V4, detail in merge-queue area).
- Section 21: Review Agent (V4, detail in review-agent area).
- Section 24: Concurrent Agent Execution (V5, detail in parallel-execution area).
- Section 28: Shared Agent Pool With AgentRole Enum (V13, detail in parallel-execution area).
- Section 29: Per-Area Concurrent Manager Invocations (V13, detail in parallel-execution area).
- Section 32: Retirement Of Batched Manager Path (V13, detail in parallel-execution area).
