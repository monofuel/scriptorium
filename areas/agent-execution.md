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
  - Pre-submit test gate (V4, §20): `submit_pr` runs `make test` before enqueuing; on failure returns error to agent with test output; on success enqueues normally (detail in merge-queue area).
- Review agent execution (V4, §21):
  - New agent role under `agents.reviewer` in `scriptorium.json`.
  - Runs in the ticket's worktree when a pending merge queue item is processed.
  - Prompt includes ticket content, diff against the default branch, area content, and submit summary.
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

- Worktree health check before retry (V8, §34):
  - Before starting any retry attempt (stall, progress timeout, or crash), validate the worktree's health.
  - Run `git status --porcelain` in the worktree; if it fails, the worktree is corrupt.
  - Run `git diff --stat` to assess uncommitted changes.
  - Corrupt worktree: remove and recreate from ticket branch (`git worktree remove --force` then `git worktree add`). Log: `ticket <id>: worktree corrupt, recreated from branch`.
  - Uncommitted changes: commit with `scriptorium: save partial agent work (attempt <n>)` on the ticket branch. Log: `ticket <id>: saved uncommitted agent work before retry`.
  - Clean worktree: proceed normally.
  - The retry agent receives the worktree in a known-good state with all prior work committed.

- Detect committed-but-not-submitted work (V8, §34):
  - At the start of each coding agent attempt (including the first), check whether the ticket branch has commits ahead of the default branch not submitted via `submit_pr`.
  - Detection: compare ticket branch HEAD against the default branch using `git log <default-branch>..<branch> --oneline`.
  - When prior work detected: log `ticket <id>: found <n> committed changes from prior attempt, agent will continue from branch tip`.
  - Include a note in the agent prompt informing the agent that prior work exists and it should review existing changes before proceeding.
  - Do not reset the branch — the agent works from the branch tip, building on prior commits.

## Spec References

- Section 5: Architect, Manager, And Coding Agent Execution.
- Section 15: Per-Ticket Metrics In Agent Run Notes (V3, detail in ticket-metrics area).
- Section 20: Pre-Submit Test Gate (V4, detail in merge-queue area).
- Section 21: Review Agent (V4, detail in review-agent area).
- Section 24: Concurrent Agent Execution (V5, detail in parallel-execution area).
- Section 34: Agent Crash Recovery — worktree health check and committed-but-not-submitted detection (V8).
