# CLI Surface And Initialization — Complete

**Area:** cli-init

All CLI surface and initialization features are fully implemented:

- **CLI entry points**: `init [path]`, `run`, `status`, `plan [prompt]`, `ask`, `worktrees`, `--version`, `--help` all functional.
- **`scriptorium init [path]`**:
  - Validates target is a git repository (fails otherwise).
  - Fails if `scriptorium/plan` branch already exists.
  - Creates orphan `scriptorium/plan` branch.
  - Creates planning structure: `areas/`, `tickets/open/`, `tickets/in-progress/`, `tickets/done/`, `decisions/`, `spec.md` placeholder.
  - Writes `.gitkeep` files in initialized directories.
  - Creates initial commit on plan branch.
  - Generates `AGENTS.md`, `Makefile`, `scriptorium.json`, and `tests/config.nims` if missing.
  - Expanded post-init output listing created files and next steps.
- **`spec.md` placeholder**: `# Spec` followed by instruction to run `scriptorium plan`.
- **Default branch detection**: `resolveDefaultBranch()` used for init and orchestrator.
- **Pre-flight validation in `run`**: Checks plan branch, AGENTS.md, Makefile with test target, agent binary, API credentials.
- **E2E test coverage**: Uses `init` subcommand for full integration testing.
