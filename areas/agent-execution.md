# Architect, Manager, And Coding Agent Execution

Covers agent-driven area generation, ticket generation, and coding agent runs.

## Scope

- Architect area generation:
  - Runs only when `spec.md` is runnable and no area markdown files exist.
  - Writes area files directly under `areas/`.
- Manager ticket generation:
  - Runs only for areas without open or in-progress tickets.
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

## Spec References

- Section 5: Architect, Manager, And Coding Agent Execution.
