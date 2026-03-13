# Review Agent Execution Flow In Merge Queue

**Area:** agent-execution

## Problem

After the `submit_review` MCP tool and reviewer config are in place (ticket 0041), the orchestrator needs to actually run a review agent session during merge queue processing, before the quality gates.

## Dependencies

- Ticket 0041 (review agent config and MCP tool) must be completed first.

## Requirements

### Review agent prompt

- Create a review agent prompt template (in `src/scriptorium/prompts/` or inline).
- Prompt includes:
  - Full ticket content (intent and requirements).
  - Diff of changes against `master` (via `git diff master...ticket-branch`).
  - Relevant area content (read from plan branch).
  - Submit summary from the coding agent.
- Instruct the review agent to call `submit_review` with `approve` or `request_changes`.

### Orchestrator integration (`orchestrator.nim`)

- In `processMergeQueue()`, after setting `active.md` but before merging master and running quality gates:
  1. Run a review agent session in the ticket's worktree using the reviewer config.
  2. After the review agent exits, consume the review decision.
  3. If approved (or stall — no `submit_review` called): proceed with existing merge flow.
  4. If changes requested:
     - Remove the pending merge queue item.
     - Append review feedback section to ticket markdown.
     - Start a new coding agent session with original ticket content plus review feedback.
     - The coding agent must call `submit_pr` again, triggering the full flow.
     - Review-driven retries count toward the ticket's total attempt count.

### Review notes in ticket markdown

- Append structured review notes: `**Review:** approved` or `**Review:** changes requested`.
- When changes requested: `**Review Feedback:** <feedback text>`.
- Include backend, exit code, and wall time consistent with agent run notes.

### Lifecycle logging

- `ticket <id>: review started (model=<model>)`
- `ticket <id>: review approved`
- `ticket <id>: review requested changes (feedback="<summary>")`
- `ticket <id>: review agent stalled, defaulting to approve`

## Acceptance Criteria

- Merge queue runs review agent before quality gates.
- Approved reviews proceed to merge.
- Stalled reviews default to approval with warning log.
- Change requests restart coding agent with feedback.
- Review notes appended to ticket markdown.
- Lifecycle log lines emitted for all review outcomes.
- Unit tests cover approve, request_changes, and stall paths.

## Spec References

- Section 21: Review Agent (V4).
