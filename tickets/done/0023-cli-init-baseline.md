# CLI Init Baseline

**Area:** cli-init
**Status:** done

## Summary

All CLI entry points and the `--init` bootstrapping flow are fully implemented and tested.

## What Exists

- CLI entry points in `src/scriptorium.nim`: `--init`, `run`, `status`, `plan`, `ask`, `worktrees`, `--version`, `--help`.
- `scriptorium --init [path]` in `init.nim`:
  - Fails if target is not a git repository.
  - Fails if `scriptorium/plan` already exists.
  - Creates orphan branch `scriptorium/plan`.
  - Creates `areas/`, `tickets/open/`, `tickets/in-progress/`, `tickets/done/`, `decisions/` directories.
  - Writes `.gitkeep` files in each initialized directory.
  - Writes `spec.md` placeholder: `# Spec\n\nRun \`scriptorium plan\` to build your spec with the Architect.`
  - Creates an initial commit on the plan branch.
- Tests: `integration_cli.nim` covers the full init flow and all CLI entry points.
