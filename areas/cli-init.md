# CLI Surface And Initialization

Covers the top-level CLI commands and the `scriptorium init` bootstrapping flow.

## Scope

- CLI entry points: `init`, `run`, `status`, `plan`, `ask`, `worktrees`, `--version`, `--help`.
- Change `scriptorium --init` flag syntax to `scriptorium init` subcommand syntax.
- `scriptorium init [path]` is the new syntax.
- `scriptorium init` validation and scaffolding:
  - Fail if target is not a git repository.
  - Fail if `scriptorium/plan` already exists.
  - Create orphan branch `scriptorium/plan`.
  - Create planning directory structure.
  - Write `.gitkeep` files in initialized directories.
  - Write `spec.md` placeholder noting this is a new project and referencing AGENTS.md.
  - Create an initial commit on the plan branch.
- Default branch detection:
  - Resolve dynamically (check `refs/remotes/origin/HEAD`, then probe for `master`/`main`/`develop`).
  - During init, run `git remote set-head origin <branch>` after resolving.
  - Error with a clear message if nothing works.
  - Replace all hardcoded `master` references in orchestrator, merge queue, and init code.
- AGENTS.md generation: on init, copy `agents_example.md` to `AGENTS.md` if missing.
- Makefile generation: on init, generate minimal Makefile with placeholder targets if missing.
- scriptorium.json generation: on init, generate with `defaultConfig()` if missing.
- Pre-flight validation in `scriptorium run`:
  - Verify `scriptorium/plan` branch, `AGENTS.md`, Makefile, make targets, agent binary, agent auth.
- Improved post-init output listing all created files and next steps.
- Update e2e test to use `scriptorium init` instead of manual seeding.

## Spec References

- Section 1: CLI Surface And Initialization.
- Section 36: Default Branch Detection.
- Section 37: Init Subcommand Syntax.
- Section 38: Init Generates AGENTS.md.
- Section 39: Init Generates Starter Makefile.
- Section 40: Init Generates scriptorium.json.
- Section 41: Pre-Flight Validation In Run.
- Section 42: Improved Post-Init Output.
- Section 43: Fresh Project Spec Placeholder.
