# Agent Execution Baseline

**Area:** agent-execution
**Status:** done

## Summary

The agent execution pipeline is fully implemented and tested.

## What Exists

- `agent_runner.nim`: Backend-agnostic `runAgent()` routing to codex or claude-code harnesses.
- `AgentStreamEvent` types: heartbeat, reasoning, tool, status, message with `AgentEventHandler` callback.
- Structured run notes: `appendAgentRunNote()` records backend, exit code, attempt, attempt count, timeout kind, log file, last-message file, last message tail, and stdout tail to ticket markdown.
- MCP `submit_pr` tool: registered on the HTTP MCP server; tool handler stores summary via thread-safe lock (`recordSubmitPrSummary` / `consumeSubmitPrSummary`).
- Merge-queue enqueueing: triggered only when `consumeSubmitPrSummary()` returns a non-empty summary, not from stdout scanning.
- Architect area generation: runs only when `spec.md` is runnable and no area files exist.
- Manager ticket generation: runs only for areas without open or in-progress tickets; write allowlist enforced to `tickets/open/`; dirty state of main repo preserved.
- Manager-generated ticket filenames assigned by orchestrator, not by agent prompt output.
- Coding agent prompt includes ticket path, ticket content, repo path, and worktree path.
- Tests: `test_agent_runner.nim`, `integration_orchestrator_live_submit_pr.nim`.
