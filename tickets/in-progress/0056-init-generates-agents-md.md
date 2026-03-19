# Init Generates AGENTS.md From Template

**Area:** cli-init

## Problem

`scriptorium init` does not generate an AGENTS.md file. New projects have no
agent instructions until the user creates one manually.

## Requirements

- During init, check if `AGENTS.md` exists in the target repo root (on the
  default branch worktree, not the plan branch).
- If missing, copy `src/scriptorium/prompts/agents_example.md` to `AGENTS.md`.
- The template already exists as a staticRead resource in prompt_catalog.nim;
  use that or read the file directly.
- Commit the new AGENTS.md on the default branch (or leave it uncommitted for
  the user to review — follow what the spec says).
- Log which files were created.

## Files To Change

- `src/scriptorium/init.nim` — add AGENTS.md generation step.
- `tests/integration_cli.nim` — verify AGENTS.md is created when missing.

## Acceptance Criteria

- Running `scriptorium init` on a repo without AGENTS.md creates one from the template.
- Running `scriptorium init` on a repo that already has AGENTS.md skips this step.
- The generated file matches `agents_example.md` content.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0056-init-generates-agents-md
