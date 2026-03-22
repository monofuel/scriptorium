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

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Well-scoped template and parameter additions across three files with clear instructions—adding placeholders to a markdown template, two string parameters to a builder function, and two file reads in the caller, minimal integration risk.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 2\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0081-include-agentsmd-and-specmd-content-in-review-agent-prompt/.scriptorium/logs/0081/attempt-02.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0081-include-agentsmd-and-specmd-content-in-review-agent-prompt/.scriptorium/logs/0081/attempt-02.last_message.txt\n
### Agent Last Message
```text
Done. All changes committed and submitted:

- **Template** (`review_agent.md`): Added `## Project Conventions (AGENTS.md)` and `## Spec Context` sections with `{{AGENTS_CONTENT}}` and `{{SPEC_CONTENT}}` placeholders.
- **Builder** (`prompt_builders.nim`): Extended `buildReviewAgentPrompt` with `agentsContent` and `specContent` parameters, bound to the template.
- **Caller** (`merge_queue.nim`): Reads `AGENTS.md` from repo root and `spec.md` from plan path, with fallback strings if missing.
- **Tests** (`test_scriptorium.nim`): Updated all existing tests with the new parameters and added a dedicated test verifying agents/spec content appears in the rendered prompt.
```

### Agent Stdout Tail
```text
Prompt` with `agentsContent` and `specContent` parameters, bound to the template.\n- **Caller** (`merge_queue.nim`): Reads `AGENTS.md` from repo root and `spec.md` from plan path, with fallback strings if missing.\n- **Tests** (`test_scriptorium.nim`): Updated all existing tests with the new parameters and added a dedicated test verifying agents/spec content appears in the rendered prompt.","stop_reason":"end_turn","session_id":"b858fc32-e1b2-4172-98ef-c05fdf4cacf3","total_cost_usd":0.31066750000000004,"usage":{"input_tokens":16,"cache_creation_input_tokens":22656,"cache_read_input_tokens":226475,"output_tokens":2230,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":22656},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":16,"outputTokens":2230,"cacheReadInputTokens":226475,"cacheCreationInputTokens":22656,"webSearchRequests":0,"costUSD":0.31066750000000004,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"208de53c-f2fb-4cf8-a14c-47072d8e8849"}
```
