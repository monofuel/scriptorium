# Review Agent

Dedicated review agent that reviews coding agent submissions before merge queue processing.

## Scope

**Review agent role:**
- Agent role configured under `agents.reviewer` in `scriptorium.json`.
- Supports the same fields as other roles: `harness`, `model`, `reasoningEffort`.
- Model-prefix harness inference applies the same as other roles.

**Review flow:**
- When the orchestrator processes a pending merge queue item, before running quality gates and merging, it runs a review agent session in the ticket's worktree.
- Review agent prompt includes:
  - Full ticket content (intent and requirements).
  - Diff of changes against `master`.
  - Relevant area content.
  - Submit summary from the coding agent.
  - The project's `AGENTS.md` content (conventions, naming, error handling, file organization).
  - Relevant `spec.md` sections (at minimum the section related to the ticket's area).
- The review agent has access to a `submit_review` MCP tool with three actions:
  - `approve`: accepts the changes, merge proceeds.
  - `approve_with_warnings`: accepts with logged warnings for minor style issues.
  - `request_changes`: rejects the changes with a `feedback` string explaining what needs to change.

**Review enforcement:**
- The review agent must enforce `AGENTS.md` conventions: check the diff against project naming, logging, error handling, and file organization rules. Flag violations.
- The review agent must enforce `spec.md` compliance: check that the implementation matches the spec and flag contradictions.
- The review agent must flag code quality issues in the diff:
  - Unreachable code or unused imports introduced by the PR.
  - Leftover artifacts from abandoned approaches (commented-out code, TODO comments referencing completed work, variables assigned but never read).
  - Changes unrelated to the ticket's stated goal (without being overly aggressive about legitimate incidental fixes).

**Graduated severity:**
- Minor style issues and small convention deviations: approve with warnings logged in review notes.
- Substantive violations (wrong behavior, spec contradictions, convention violations affecting correctness, dead code, unrelated changes): request changes.

**Review outcomes:**
- Approved: merge queue proceeds with existing quality gate flow (merge master, run tests, fast-forward merge).
- Approved with warnings: merge proceeds, warnings logged in review notes.
- Changes requested:
  - Pending merge queue item is removed.
  - Ticket remains in `tickets/in-progress/`.
  - Review feedback appended to ticket markdown.
  - New coding agent session started with original ticket content plus review feedback, using the same worktree and branch.
  - Review-driven retries count toward the ticket's total attempt count.
- Stall (review agent exits without calling `submit_review`):
  - Treat as approval — merge proceeds.
  - Log warning: `ticket <id>: review agent stalled, defaulting to approve`.

**Review lifecycle logging:**
- Review start, approved, approved-with-warnings, changes requested, and stall events are all logged at INFO level with ticket ID.
- Review outcomes appended to ticket markdown as structured review notes.
- Review reasoning (not just the decision) must be logged so violations are traceable in the review logs.

## Spec References

- Section 9: Review Agent.
