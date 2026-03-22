# 0102-fix-claude-code-continuation-prompt-builder-forwarding

**Area:** harness-backends

## Summary

Fix `agent_runner.nim` to forward the `continuationPromptBuilder` field when routing through the Claude Code harness, matching the codex and typoi paths.

## Context

In `src/scriptorium/agent_runner.nim`, the `harnessCodex` case (line 120) and `harnessTypoi` case (line 189) both forward `request.continuationPromptBuilder` to their respective run request objects. The `harnessClaudeCode` case (line 156) does **not** forward this field, even though `ClaudeCodeRunRequest` has a `continuationPromptBuilder` field (defined in `harness_claude_code.nim` line 57).

This means Claude Code retry attempts always use the static `continuationPrompt` text instead of the dynamic builder, which is a bug for any caller that sets `continuationPromptBuilder`.

## Requirements

1. In `src/scriptorium/agent_runner.nim`, add `continuationPromptBuilder: request.continuationPromptBuilder` to the `ClaudeCodeRunRequest` construction inside the `harnessClaudeCode` case (around line 156-176).
2. Add a unit test in `tests/test_agent_runner.nim` that verifies a `continuationPromptBuilder` set on `AgentRunRequest` is invoked during Claude Code retry (use a fake binary that exits non-zero on first attempt, then exits 0 on second attempt, and assert the builder was called).

## Notes

- Follow the existing test patterns in `test_agent_runner.nim` using `writeExecutableScript` for fake binaries.
- Set `maxAttempts: 2` on the request to trigger retry logic.
