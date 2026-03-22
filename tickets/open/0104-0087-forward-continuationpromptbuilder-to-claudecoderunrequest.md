# 0087 — Forward continuationPromptBuilder to ClaudeCodeRunRequest

**Area:** compaction-context

**File:** `tickets/open/0087-forward-builder-claude-code.md`

## Problem

In `src/scriptorium/agent_runner.nim`, the `continuationPromptBuilder` field from `AgentRunRequest` is forwarded to `CodexRunRequest` (line 137) and `TypoiRunRequest` (line 205), but is **not** forwarded to `ClaudeCodeRunRequest` (lines 156–176). The Claude Code branch only forwards `continuationPrompt` (the static string), not `continuationPromptBuilder` (the dynamic callback).

## Task

In `src/scriptorium/agent_runner.nim`, add `continuationPromptBuilder: request.continuationPromptBuilder` to the `ClaudeCodeRunRequest` construction (around line 171, next to the existing `continuationPrompt` field).

## Verification

- `nim r src/scriptorium.nim` compiles without errors.
- `make test` passes.
- Grep for `continuationPromptBuilder` in `agent_runner.nim` — it should appear three times in the dispatch (codex, claude code, typoi).
