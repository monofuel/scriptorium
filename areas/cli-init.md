# CLI Surface And Initialization

Covers the top-level CLI commands and the `scriptorium init` bootstrapping flow for fresh and existing projects.

## Scope

- CLI entry points: `init`, `run`, `status`, `plan`, `ask`, `do`, `audit`, `dashboard`, `discord`, `mattermost`, `sync`, `worktrees`, `--version`, `--help`.
- `scriptorium init [path]` is a subcommand (V11, §37), replacing the former `--init` flag syntax. `--init` may be kept as a deprecated alias or dropped.

**Init validation and scaffolding:**
- Fail if target is not a git repository.
- Fail if `scriptorium/plan` already exists.
- Resolve the default branch dynamically (V11, §36, see orchestrator area for resolution logic).
- Run `git remote set-head origin <branch>` after resolving the default branch so future runs skip the probe.
- Create orphan branch `scriptorium/plan`.
- Create planning directory structure: `areas/`, `tickets/open/`, `tickets/in-progress/`, `tickets/done/`, `decisions/`.
- Write `.gitkeep` files in initialized directories.
- Write updated `spec.md` placeholder (V11, §43):
  ```
  # Spec

  This is a new project. See AGENTS.md for project conventions.

  Run `scriptorium plan` to build your spec with the Architect.
  ```
- Create an initial commit on the plan branch.

**Init generates default-branch artifacts (V11):**
- If `AGENTS.md` does not exist on the default branch, copy `agents_example.md` to `AGENTS.md` and commit it (§38). Print: `Created AGENTS.md — edit to match your project conventions.`
- If no Makefile exists on the default branch, generate a minimal one with placeholder `test`, `integration-test`, and `e2e-test` targets that exit 0 (§39). Commit it. Print: `Created Makefile with placeholder targets — replace with real build commands.`
- If no `scriptorium.json` exists, generate one using `defaultConfig()` and write it to the repo root (§40). Do NOT commit it — it may contain user-specific preferences. Print: `Created scriptorium.json — configure agent models and harnesses.`
- Existing files are never overwritten by init.

**Project opinions (V11, §35):**
- Scriptorium is opinionated about managed project structure. These opinions are rigid:
  - Nim is the implementation language. nimby is the dependency manager.
  - Required structure: `src/`, `tests/`, `Makefile`, `AGENTS.md`, `scriptorium.json`, `docs/`.
  - Required make targets: `make build`, `make test` (fast, no network), `make integration-test` (may require credentials), `make e2e-test` (optional).

**Improved post-init guidance (V11, §42):**
- After init completes, output lists all created artifacts with descriptions and numbered next steps.
- Only list artifacts that were actually created (skip items that already existed).
- Output format includes: created artifacts section, next steps section with instructions to configure models, edit AGENTS.md, run `scriptorium plan`, and run `scriptorium run`.

## Spec References

- Section 1: CLI Surface And Initialization.
- Section 35: Project Opinions (V11).
- Section 36: Default Branch Detection (V11, resolution logic in orchestrator area).
- Section 37: CLI Init Subcommand (V11).
- Section 38: Init Generates AGENTS.md (V11).
- Section 39: Init Generates Starter Makefile (V11).
- Section 40: Init Generates Starter scriptorium.json (V11).
- Section 42: Improved Post-Init Guidance (V11).
- Section 43: Updated Spec Placeholder (V11).
