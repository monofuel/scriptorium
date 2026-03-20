# Improved Post-Init Output

**Area:** cli-init
**Depends:** 0054, 0056, 0057, 0058

## Problem

Current post-init output is minimal — it only shows the plan branch name and
two next-step commands. It does not list the files that were created or provide
guidance on configuring the generated files.

## Requirements

- After init completes, list all files and branches that were created:
  - Plan branch and its directory structure.
  - AGENTS.md (if generated).
  - Makefile (if generated).
  - scriptorium.json (if generated).
  - spec.md placeholder.
- Provide next-step guidance:
  - Edit AGENTS.md to describe your project.
  - Edit scriptorium.json to configure models and harness.
  - Edit Makefile to set up real test/build targets.
  - Run `scriptorium plan` to build your spec.
  - Run `scriptorium run` to start the orchestrator.
- Update the spec.md placeholder text to reference AGENTS.md.

## Files To Change

- `src/scriptorium/init.nim` — expand post-init output, update spec.md placeholder.
- `tests/integration_cli.nim` — verify expanded output.

## Acceptance Criteria

- Post-init output lists every created file.
- Post-init output includes actionable next steps for each generated file.
- spec.md placeholder references AGENTS.md.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0060-improved-post-init-output
