# Detect Committed-But-Not-Submitted Work

**Area:** agent-execution

Implement detection of prior commits on the ticket branch that were not submitted via `submit_pr`, as specified in V8, §34.

## Requirements

At the start of each coding agent attempt (including the first), check whether the ticket branch has commits ahead of `master`:

1. **Detection:** Run `git log master..<branch> --oneline` in the worktree to find commits ahead of master.
2. **When prior work detected:**
   - Log: `ticket <id>: found <n> committed changes from prior attempt, agent will continue from branch tip`.
   - Include a note in the agent prompt informing the agent that prior work exists and it should review existing changes before proceeding.
3. **Do not reset the branch** — the agent works from the branch tip, building on prior commits.

## Implementation Notes

- Add detection logic in `executeAssignedTicket` in `coding_agent.nim`, before building the prompt for each attempt.
- Use `runCommandCapture` to run `git log master..<branch> --oneline` and count lines.
- Extend `buildCodingAgentPrompt` (or create a wrapper) to accept an optional prior-work note that gets prepended/appended to the prompt.
- The initial prompt and continuation prompts should both include the prior-work note when applicable.

## Acceptance Criteria

- Prior commits on the ticket branch are detected at each attempt start.
- Log message emitted with correct commit count.
- Agent prompt includes prior-work awareness note when commits exist.
- No branch reset occurs — agent continues from branch tip.
- Unit tests cover: no prior work, prior work detected with correct count.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0064-detect-committed-not-submitted-work

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Single-file change in coding_agent.nim adding a git log check and string interpolation into the prompt builder, with straightforward unit tests for line counting logic.
