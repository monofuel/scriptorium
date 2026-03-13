# Review Agent Prompt And Feedback Unit Tests

**Area:** review-agent

## Problem

V7 §30 requires unit test coverage for `buildReviewAgentPrompt`, diff edge cases, and feedback truncation. These tests do not currently exist (confirmed by searching `tests/` for review prompt/truncation test patterns).

## Requirements

### buildReviewAgentPrompt tests
- Verify the rendered prompt contains expected sections: diff, ticket content, area context, submit summary.
- Verify each section is labeled and delimited so the review agent can parse them.
- Verify the prompt includes review instructions and available MCP tool description (`submit_review`).

### Diff edge case tests
- Empty diff: prompt must include a note that no changes were found and the review agent should flag this.
- Verify the review flow handles a failed/empty diff gracefully — the prompt builder should not crash on empty input.

### Feedback truncation tests
- `ReviewFeedbackMaxBytes` is defined as 4096 in `orchestrator.nim`.
- Test feedback well under 4096 bytes: passes through unchanged.
- Test feedback exactly 4096 bytes: passes through unchanged.
- Test feedback at 4097 bytes: truncated with `... [truncated]` marker.

## Acceptance Criteria

- All tests added to `tests/test_scriptorium.nim` (or a new `tests/test_review_agent.nim`).
- Tests exercise `buildReviewAgentPrompt` with realistic inputs.
- Tests exercise feedback truncation boundary conditions.
- `make test` passes.
