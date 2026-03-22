# Compaction-Resilient Agent Context

Ensures agent continuations re-inject project rules after context compaction.

## Scope

- When scriptorium builds a continuation prompt for a retry or timeout recovery, re-inject the project's `AGENTS.md` rules (or a condensed version) into the continuation text.
- The continuation prompt builder has access to the working directory and can read `AGENTS.md`.
- The `continuationPromptBuilder` must be forwarded to `ClaudeCodeRunRequest` in `agent_runner.nim` (currently only forwarded for codex/typoi harnesses).
- Critical `AGENTS.md` rules should be present in `CLAUDE.md` (or `.claude/` config files) for compaction resilience, since Claude Code reloads `CLAUDE.md` after compaction.

## Spec References

- Section 20: Compaction-Resilient Agent Context.
