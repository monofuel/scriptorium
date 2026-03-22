# Review prompt: include AGENTS.md and spec.md content

**Area:** agent-execution

The review agent prompt is missing two required context sections per spec section 9.

## Current State

`buildReviewAgentPrompt` in `src/scriptorium/prompt_builders.nim` accepts only `ticketContent`, `diffContent`, `areaContent`, and `submitSummary`. The `review_agent.md` prompt template has no placeholders for AGENTS.md or spec.md content.

## Required Changes

1. Add `{{AGENTS_MD_CONTENT}}` and `{{SPEC_SECTIONS}}` placeholders to `src/scriptorium/prompts/review_agent.md`. Place them in new sections titled "## Project Conventions (AGENTS.md)" and "## Spec Context" between the Area Context and Instructions sections.

2. Update `buildReviewAgentPrompt` in `src/scriptorium/prompt_builders.nim` to accept two additional parameters: `agentsMdContent: string` and `specSections: string`. Pass them as bindings to `renderPromptTemplate`.

3. Update the call site in `runReviewAgent` (`src/scriptorium/merge_queue.nim`) to:
   - Read `AGENTS.md` from the repo root (`repoPath / "AGENTS.md"`).
   - Read relevant spec sections from the plan worktree. At minimum, find the section matching the ticket's area by searching `spec.md` headings. A simple approach: extract all `## N.` section headings, find the one whose title best matches the area ID, and include that section plus any subsections until the next top-level `##` heading.
   - Pass both values to `buildReviewAgentPrompt`.

4. Update the review prompt instructions section to direct the reviewer to check the diff against AGENTS.md conventions and spec.md compliance, matching the Review Enforcement rules in spec section 9.

5. Update any tests in `tests/` that call `buildReviewAgentPrompt` to pass the new parameters.

## Verification

- `make test` passes.
- The rendered review prompt includes AGENTS.md and spec section content.
