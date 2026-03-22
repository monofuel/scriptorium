# 0109 — Pass continuationPromptBuilder for Claude Code in agent_runner

**Area:** harness-backends

## Problem

In `src/scriptorium/agent_runner.nim`, the `runAgent` dispatch for `harnessClaudeCode` (lines 155–176) does not pass `continuationPromptBuilder` to the `ClaudeCodeRunRequest`. The codex branch (line 137) and typoi branch (line 205) both pass it. The `ClaudeCodeRunRequest` type already has the field (`harness_claude_code.nim:57`), and `buildContinuationPrompt` in `harness_claude_code.nim:604` already uses it.

This means Claude Code retry attempts always fall back to the default continuation text, ignoring any custom builder the caller provides.

## Changes

1. **`src/scriptorium/agent_runner.nim`**: Add `continuationPromptBuilder: request.continuationPromptBuilder,` to the `ClaudeCodeRunRequest` constructor in the `harnessClaudeCode` branch (around line 171, alongside the existing `continuationPrompt` field).

2. **`tests/test_harness_claude_code.nim`**: Add a unit test that verifies a custom `continuationPromptBuilder` is invoked during retry. Use a fake claude binary that exits non-zero on the first attempt and zero on the second, with `maxAttempts: 2`. Confirm the builder proc was called by checking a captured flag or the prompt content in the second attempt's log.

## Validation

- `make test` passes.
- The new test confirms the builder is actually called during Claude Code retries.
