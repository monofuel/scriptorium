<!-- ticket: 0075-review-prompt-agents-spec-content.md -->
# Include AGENTS.md and spec.md content in review agent prompt

**Area:** review-agent
**Difficulty:** medium

## Problem

The review agent prompt (in `src/scriptorium/prompts/review_agent.md`) currently includes ticket content, diff, area content, and submit summary. Per the spec (Section 9), it must also include:
- The project's `AGENTS.md` content (conventions, naming, error handling, file organization).
- Relevant `spec.md` sections (at minimum the section related to the ticket's area).

Without this context, the review agent cannot enforce project conventions or spec compliance.

## Requirements

1. **Prompt template** (`src/scriptorium/prompts/review_agent.md`):
   - Add a new section `## Project Conventions (AGENTS.md)` with placeholder `{{AGENTS_CONTENT}}`.
   - Add a new section `## Spec Context` with placeholder `{{SPEC_CONTENT}}`.
   - Place these sections after `## Area Context` and before `## Instructions`.

2. **Prompt builder** (`src/scriptorium/prompt_builders.nim`):
   - Update `buildReviewAgentPrompt` signature to accept `agentsContent: string` and `specContent: string` parameters.
   - Add the two new bindings to the `renderPromptTemplate` call.

3. **Review agent caller** (`src/scriptorium/merge_queue.nim:183-268`, `runReviewAgent`):
   - Read `AGENTS.md` from the repo root (`repoPath / "AGENTS.md"`). If missing, use `"(AGENTS.md not found)"`.
   - Read the relevant spec section from the plan branch. The area ID is already parsed. Extract the spec section whose heading matches the area's `## Spec References` entry. If extraction is too complex, include the full `spec.md` content (it's read from `planPath / "spec.md"`). If missing, use `"(spec not available)"`.
   - Pass both to `buildReviewAgentPrompt`.

4. **Tests**:
   - Update existing `buildReviewAgentPrompt` unit tests to pass the new parameters.
   - Add a test verifying that AGENTS.md and spec content appear in the rendered prompt.

## Key files
- `src/scriptorium/prompts/review_agent.md` — prompt template
- `src/scriptorium/prompt_builders.nim:84-94` — `buildReviewAgentPrompt`
- `src/scriptorium/merge_queue.nim:183-268` — `runReviewAgent`
- `tests/test_scriptorium.nim` — prompt builder tests

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0081-include-agentsmd-and-specmd-content-in-review-agent-prompt
