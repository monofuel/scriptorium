# CLI Surface And Initialization

Covers the top-level CLI commands and the `--init` bootstrapping flow.

## Scope

- CLI entry points: `--init`, `run`, `status`, `plan`, `ask`, `worktrees`, `--version`, `--help`.
- `scriptorium --init [path]` validation and scaffolding:
  - Fail if target is not a git repository.
  - Fail if `scriptorium/plan` already exists.
  - Create orphan branch `scriptorium/plan`.
  - Create planning directory structure: `areas/`, `tickets/open/`, `tickets/in-progress/`, `tickets/done/`, `decisions/`.
  - Write `.gitkeep` files in initialized directories.
  - Write `spec.md` placeholder with heading and run-plan prompt.
  - Create an initial commit on the plan branch.

## Spec References

- Section 1: CLI Surface And Initialization.
