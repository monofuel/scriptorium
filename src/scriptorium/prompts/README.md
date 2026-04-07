# Prompt Templates

All model-facing prompt text is centralized in this directory and bundled at compile time via `staticRead()`.

Prompt path terminology should stay aligned with `docs/terms.md`.

## Placeholder Style

- Placeholders use `{{UPPER_SNAKE_CASE}}` markers.
- Runtime renderers must provide all placeholders expected by a template.
- Rendering fails fast when placeholders are missing or unresolved.

## Templates

- `coding_agent.md`: coding-agent ticket execution prompt.
- `architect_areas.md`: Architect area generation prompt.
- `manager_tickets.md`: Manager ticket generation prompt.
- `agents_example.md`: generic example `AGENTS.md` content for generated fixture repositories.
- `plan_scope.md`: shared plan worktree context with write scope (used by plan and loop prompts).
- `plan_scope_readonly.md`: shared plan worktree context with read-only scope (used by ask prompts).
- `tone.md`: shared communication tone directive (appended to all agent prompts).
- `repo_hygiene.md`: shared repository hygiene directive (appended to all action-taking agent prompts).
- `engineering_method.md`: shared engineering method directive (Five Whys, root cause analysis — appended to all agent prompts).
- `architect_loop.md`: Architect loop-driven development cycle prompt.
- `architect_plan_oneshot.md`: one-shot `scriptorium plan <prompt>` prompt.
- `architect_plan_interactive.md`: per-turn interactive `scriptorium plan` prompt.
- `codex_retry_continuation.md`: retry continuation prompt for codex harness.
- `codex_retry_default_continuation.md`: default retry continuation sentence.

## Agent Completion Tool

Coding-agent prompts must instruct the model to call the `submit_pr` MCP tool
when work is complete. The orchestrator uses that tool call to enqueue merge
requests, so completion signaling must not rely on stdout text patterns.
