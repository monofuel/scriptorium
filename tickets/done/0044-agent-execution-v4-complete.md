# Agent Execution Area — V4 Complete

**Area:** agent-execution
**Status:** done

## Summary

All agent-execution scope items through V4 are fully implemented and tested:

- **Architect area generation**: Content-hash driven via `areas/.spec-hash`. Migration, first-run, and re-run paths all work. Hash marker committed separately after area generation.
- **Manager ticket generation**: Content-hash driven via `tickets/.area-hashes`. Legacy fallback (no hash file) suppresses all areas with any ticket. Current mode re-tickets areas whose content changed. Batched execution with write-prefix allowlist. Repo dirty state preserved.
- **Coding agent execution**: Prompt includes ticket path, content, repo path, and worktree path. Structured agent run notes appended after each attempt. MCP `submit_pr` tool used for merge queue enqueueing (no stdout scanning).
- **Pre-submit test gate (V4 §20)**: `submit_pr` runs `make test` before accepting. On failure, returns error to agent with test output. On success, enqueues normally. Logged with pass/fail, exit code, and wall time.
- **Review agent (V4 §21)**: `agents.reviewer` config key. `submit_review` MCP tool with `approve` and `request_changes` actions. Review runs before merge for every pending queue item. Stall defaults to approval. Review notes appended to ticket.
- **Per-ticket metrics (V3 §15)**: All 8 required fields tracked and persisted: `wall_time_seconds`, `coding_wall_seconds`, `test_wall_seconds`, `attempt_count`, `outcome`, `failure_reason`, `model`, `stdout_bytes`.

Concurrent agent execution (V5 §24) is scoped to the parallel-execution area.

## Prior Tickets

- 0022: Agent execution baseline
- 0040: Pre-submit test gate
- 0041: Review agent config and MCP tool
- 0042: Review agent execution flow
