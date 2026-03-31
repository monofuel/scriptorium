# 0077 Update init output to match V11 post-init guidance

**Area:** cli-init

**Depends:** 0074, 0075, 0076

## Description

Per V11 §42, §38, §39, §40, the init output must:
- Print a specific message per artifact as it is created:
  - `Created AGENTS.md — edit to match your project conventions.` (§38)
  - `Created Makefile with placeholder targets — replace with real build commands.` (§39)
  - `Created scriptorium.json — configure agent models and harnesses.` (§40)
- After all creation, output a summary with:
  - A "Created artifacts" section listing only items that were actually created (skip items that already existed).
  - A numbered "Next steps" section with instructions to: (1) configure models in scriptorium.json, (2) edit AGENTS.md, (3) run `scriptorium plan`, (4) run `scriptorium run`.
  - Only list next steps relevant to what was created.

## Current behavior

The current output in `src/scriptorium/init.nim` lines 166-197 uses unnumbered bullet-style next steps and different wording.

## Tasks

1. In `src/scriptorium/init.nim`, update the post-init output block (lines 166-197) to:
   - Print per-artifact messages during creation (inline with each creation block).
   - Print a final summary with numbered next steps.
2. Update `tests/integration_cli.nim` test "init output lists created files and next steps" to match the new output format, checking for:
   - The specific per-artifact messages from §38, §39, §40.
   - Numbered next steps.
3. Run `make test` to confirm.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0084-0077-update-init-output-to-match-v11-post-init-guidance
