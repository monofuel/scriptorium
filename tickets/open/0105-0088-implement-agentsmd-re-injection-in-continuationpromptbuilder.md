# 0088 — Implement AGENTS.md re-injection in continuationPromptBuilder

**Area:** compaction-context

**Depends:** 0087

**File:** `tickets/open/0088-agents-md-continuation-builder.md`

## Problem

The `continuationPromptBuilder` callback is defined (`ContinuationPromptBuilder` in `src/scriptorium/common.nim`) and wired through all three harnesses, but it is never set when creating `AgentRunRequest` objects. After context compaction or a retry, the agent loses AGENTS.md rules and drifts from project conventions.

## Task

1. Create a proc (e.g., `buildAgentsRulesReminder`) in `src/scriptorium/prompt_builders.nim` that:
   - Takes `workingDir: string` as its parameter (matching `ContinuationPromptBuilder` signature).
   - Reads `AGENTS.md` from `workingDir` (falling back to the project repo path if not found).
   - Returns a string like: `"Reminder: Follow the project rules from AGENTS.md:\n\n" & agentsContent`
   - If AGENTS.md cannot be read, returns an empty string (no crash).

2. In `src/scriptorium/coding_agent.nim`, when constructing the `AgentRunRequest`, set `continuationPromptBuilder` to a closure that calls the new proc. The coding agent is the primary long-running agent that hits compaction.

## Verification

- `make test` passes.
- Manually verify: create a test that calls the new proc with a temp directory containing an AGENTS.md and confirms the reminder text is returned.
