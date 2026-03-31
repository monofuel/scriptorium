Review Agent

V4 feature: a dedicated review agent that reviews coding agent submissions before merge queue processing.

Scope:

**Review agent role:**
- New agent role with configuration under `agents.reviewer` in `scriptorium.json`.
- Supports the same fields as other roles: `harness`, `model`, `reasoningEffort`.
- Model-prefix harness inference applies the same as other roles.

**Review flow:**
- When the orchestrator processes a pending merge queue item, before running quality gates and merging, it must run a review agent session in the ticket's worktree.
- Review agent prompt includes:
  - Full ticket content (intent and requirements).
  - Diff of changes against the default branch (via `git diff <default-branch>...ticket-branch`).
  - Relevant area content.
  - Submit summary from the coding agent.
- The review agent has access to a `submit_review` MCP tool with two actions:
  - `approve`: accepts the changes, merge proceeds.
  - `request_changes`: rejects the changes with a `feedback` string explaining what needs to change.
- The review agent must call `submit_review` to signal its decision.

**Review outcomes:**
- Approved: merge queue proceeds with existing quality gate flow (merge default branch, run tests, fast-forward merge).
- Changes requested:
  - Pending merge queue item is removed.
  - Ticket remains in `tickets/in-progress/`.
  - Review feedback section appended to ticket markdown with reviewer's feedback.
  - New coding agent session started with original ticket content plus review feedback, using the same worktree and branch.
  - Coding agent must call `submit_pr` again when done, triggering the full flow again (pre-submit tests, then review).
  - Review-driven retries count toward the ticket's total attempt count.
- Stall (review agent exits without calling `submit_review`):
  - Treat as approval — merge proceeds.
  - Log warning: `ticket <id>: review agent stalled, defaulting to approve`.

**Review lifecycle logging:**
- Review start: `ticket <id>: review started (model=<model>)`.
- Review approved: `ticket <id>: review approved`.
- Review changes requested: `ticket <id>: review requested changes (feedback="<summary>")`.
- Review stall: `ticket <id>: review agent stalled, defaulting to approve`.

**Review agent notes:**
- Review outcomes appended to ticket markdown as structured review notes:
  - `**Review:** approved` or `**Review:** changes requested`.
  - `**Review Feedback:** <feedback text>` (when changes requested).
  - Backend, exit code, and wall time, consistent with existing agent run notes.

**Test coverage (V7, §30):**
- Required unit tests for `buildReviewAgentPrompt`:
  - Verify the rendered prompt contains expected sections: diff, ticket content, area context, submit summary.
  - Verify each section is labeled and delimited so the review agent can parse them.
  - Verify the prompt includes review instructions and available MCP tool description.
- Edge case tests for diff generation:
  - Empty diff: prompt must include a note that no changes were found and the review agent should flag this.
  - Failed diff: review flow must handle gracefully — log warning and default to approval rather than crashing.
- Feedback truncation:
  - When review feedback exceeds `ReviewFeedbackMaxBytes` (4096 bytes), it must be truncated with a `... [truncated]` marker.
  - Unit tests must exercise the truncation boundary: exactly 4096 bytes, 4097 bytes, and well under 4096 bytes.
- Live integration test:
  - Run the review agent with a real model (similar to `integration_mcp_submit_pr_live.nim`).
  - Verify the review agent calls `submit_review` with either `approve` or `request_changes`.
  - Use a real diff against a real branch, not synthetic input.

**Known Limitations:**
- Single-pass reviewer — no back-and-forth dialogue with the coding agent.
- Change requests restart the coding agent from scratch rather than resuming the previous session.
- Stall-default-to-approve policy prioritizes throughput over review quality — future versions may retry the reviewer instead.
- Review agent live integration tests require API credentials and a running model, so they only run in `make integration-test`, not `make test`.
