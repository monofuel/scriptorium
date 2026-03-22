# 0105 — Wire continuationPromptBuilder for Claude Code in agent_runner

**Area:** harness-backends

## Problem

In `src/scriptorium/agent_runner.nim`, the `runAgent` proc passes `continuationPromptBuilder` when building `CodexRunRequest` (line 137) and `TypoiRunRequest` (line 205), but omits it when building `ClaudeCodeRunRequest` (lines 156–176). This means Claude Code retries never use the dynamic continuation prompt builder, falling back to the static `continuationPrompt` string or the default text.

## Requirements

1. In `src/scriptorium/agent_runner.nim`, add `continuationPromptBuilder: request.continuationPromptBuilder` to the `ClaudeCodeRunRequest` construction in the `harnessClaudeCode` branch of `runAgent`.
2. Add a unit test in `tests/test_agent_runner.nim` that verifies a Claude Code retry uses the `continuationPromptBuilder` when provided. Use a fake claude script that fails on the first attempt and succeeds on the second; provide a `continuationPromptBuilder` that returns a known marker string; verify the second attempt's prompt contains that marker.

## Key files

- `src/scriptorium/agent_runner.nim:171` — the missing field
- `tests/test_agent_runner.nim` — existing agent runner tests
