# 0085 — Add `--init` as CLI alias for `init` subcommand

**Area:** cli-init

## Problem

The area spec defines the init entry point as `scriptorium --init [path]`, but the
current CLI only recognizes `scriptorium init [path]`. The `--init` flag form is not
handled.

## Requirements

- Add `"--init"` as an additional case in the CLI argument parser in
  `src/scriptorium.nim` (line ~107), alongside the existing `"init"` case.
  Both `scriptorium init [path]` and `scriptorium --init [path]` must work identically.
- Update the `Usage` help string to show `--init` as the primary form
  (keep `init` working as well).
- Add a test in `tests/integration_cli.nim` that runs the compiled binary with
  `--init` and verifies it initializes successfully (creates the `scriptorium/plan`
  branch).

## Key files

- `src/scriptorium.nim` — CLI entry point, `case args[0]` block and `Usage` constant
- `tests/integration_cli.nim` — integration tests for CLI commands
````

---

````markdown
# 0086 — Update spec.md placeholder to match area spec

**Area:** cli-init

## Problem

The area spec requires the initialized `spec.md` placeholder to be exactly:
