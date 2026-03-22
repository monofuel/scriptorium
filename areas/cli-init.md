# CLI Surface And Initialization

Covers the top-level CLI commands and the `scriptorium --init` bootstrapping flow.

## Scope

- CLI entry points: `--init`, `run`, `status`, `plan`, `ask`, `audit`, `worktrees`, `--version`, `--help`.
- `scriptorium --init [path]` must:
  - Fail if target is not a git repository.
  - Fail if `scriptorium/plan` already exists.
  - Create orphan branch `scriptorium/plan`.
  - Create planning structure:
    - `areas/`
    - `tickets/open/`
    - `tickets/in-progress/`
    - `tickets/done/`
    - `decisions/`
    - `spec.md` placeholder.
  - Write `.gitkeep` files in initialized directories.
  - Create an initial commit on the plan branch.
- The initialized `spec.md` placeholder must be:
  - `# Spec`
  - blank line
  - `` Run `scriptorium plan` to build your spec with the Architect. ``

## Spec References

- Section 1: CLI Surface And Initialization.
