# Concurrent Agent Execution With Isolated Worktrees

**Area:** parallel-execution

## Problem

With the non-blocking tick (ticket 0049) providing the framework, the actual concurrent agent execution needs to be wired up: multiple coding agent processes running in parallel, each in its own worktree, with independent lifecycle management.

## Requirements

1. Each agent slot runs its coding agent process in a separate thread or as a separate subprocess, fully isolated in its own worktree.
2. Thread-safe shared state for MCP tool handlers (`submit_pr`, `submit_review`):
   - The current `activeWorktreePathBuffer`/`activeTicketIdBuffer` pattern supports only one active agent. Refactor to support per-ticket state so MCP handlers can identify which ticket is calling.
   - Option: use ticket ID from MCP request context, or maintain a concurrent map of active agents.
3. Stall detection (no-output timeout, hard timeout) applies independently per running agent.
4. Continuation prompts on stall apply per-agent — one agent stalling does not affect others.
5. Per-ticket metrics tables (`ticketStartTimes`, `ticketCodingWalls`, etc.) are already keyed by ticket ID and should work concurrently, but verify thread safety.
6. Add integration test verifying two agents can run concurrently in separate worktrees without interfering.

## Dependencies

- Ticket 0049 (non-blocking tick with agent tracking)

## Acceptance Criteria

- `make test` passes.
- Two coding agents can run simultaneously when `maxAgents >= 2`.
- MCP `submit_pr` correctly identifies the calling agent's ticket.
- Stall detection works independently per agent.
