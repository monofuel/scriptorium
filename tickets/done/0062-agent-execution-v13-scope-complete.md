# Agent Execution — V13 Scope Summary

**Area:** agent-execution

All agent-execution scope items through V4 are fully implemented:

- **Architect area generation**: Content-hash driven via `areas/.spec-hash`, migration for legacy state, runs only when spec hash changes.
- **Manager ticket generation**: Content-hash driven via `tickets/.area-hashes`, suppresses areas with open/in-progress tickets, write-prefix allowlist to `tickets/open/`.
- **Coding agent execution**: Runs in assigned ticket worktree, prompt includes ticket path/content/repo/worktree, structured agent run notes appended to ticket markdown.
- **MCP `submit_pr` tool**: Thread-safe merge queue enqueueing via MCP tool state (not stdout scanning).
- **Pre-submit test gate** (V4 §20): `submit_pr` runs `make test` before enqueuing; failure returns error to agent.
- **Review agent execution** (V4 §21): Runs in ticket worktree, prompt includes ticket/diff/area/summary, `submit_review` MCP tool with approve/request_changes, stall defaults to approval.
- **Per-ticket metrics** (V3 §15): All required fields persisted (wall_time_seconds, coding_wall_seconds, test_wall_seconds, attempt_count, outcome, failure_reason, model, stdout_bytes).
- **Concurrent agent execution** (V5 §24): Multiple coding agents in parallel isolated worktrees with independent lifecycle.

V13 changes to manager execution model (§28 shared agent pool, §29 per-area concurrent managers, §32 batched retirement) are scoped to and tracked in the parallel-execution area.
