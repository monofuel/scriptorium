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
  - Diff of changes against `master` (via `git diff master...ticket-branch`).
  - Relevant area content.
  - Submit summary from the coding agent.
- The review agent has access to a `submit_review` MCP tool with two actions:
  - `approve`: accepts the changes, merge proceeds.
  - `request_changes`: rejects the changes with a `feedback` string explaining what needs to change.
- The review agent must call `submit_review` to signal its decision.

**Review outcomes:**
- Approved: merge queue proceeds with existing quality gate flow (merge master, run tests, fast-forward merge).
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

**V4 Known Limitations:**
- Single-pass reviewer — no back-and-forth dialogue with the coding agent.
- Change requests restart the coding agent from scratch rather than resuming the previous session.
- Stall-default-to-approve policy prioritizes throughput over review quality — future versions may retry the reviewer instead.
