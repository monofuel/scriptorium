<!-- ticket: 0076-review-prompt-enforcement-instructions.md -->
# Add enforcement and graduated severity instructions to review agent prompt

**Area:** review-agent
**Depends:** 0075

## Problem

The review agent prompt's `## Instructions` section is minimal — it only says to approve or request changes based on ticket requirements. Per the spec (Section 9), the prompt must include explicit instructions for:
- Enforcing `AGENTS.md` conventions (naming, logging, error handling, file organization).
- Enforcing `spec.md` compliance (implementation matches spec, no contradictions).
- Flagging code quality issues (unreachable code, unused imports, leftover artifacts, unrelated changes).
- Graduated severity (minor issues → approve with warnings; substantive violations → request changes).

## Requirements

1. **Update prompt template** (`src/scriptorium/prompts/review_agent.md`):
   - Replace the current `## Instructions` section with detailed enforcement instructions. The new instructions should cover:
     - **Convention enforcement:** Check the diff against `AGENTS.md` rules — naming conventions, import style, error handling patterns, comment style, variable grouping. Flag violations.
     - **Spec compliance:** Check that the implementation matches the spec section provided. Flag contradictions or missing required behavior.
     - **Code quality:** Flag unreachable code, unused imports introduced by the PR, leftover artifacts (commented-out code, TODO comments for completed work, assigned-but-unread variables), and changes unrelated to the ticket goal (but don't be aggressive about legitimate incidental fixes).
     - **Graduated severity:**
       - Minor style issues and small convention deviations → use `approve_with_warnings` with warnings describing the issues.
       - Substantive violations (wrong behavior, spec contradictions, convention violations affecting correctness, dead code, unrelated changes) → use `request_changes` with clear feedback.
     - Keep the instruction that `submit_review` must be called exactly once.
     - Keep the CRITICAL instruction about verifying the tool is available.

2. **No code changes needed** — this is a prompt-only change. The template placeholders are unchanged.

3. **Tests**: Verify the prompt template still renders correctly with existing tests (no new placeholders introduced).

## Key files
- `src/scriptorium/prompts/review_agent.md` — prompt template (only file to modify)
