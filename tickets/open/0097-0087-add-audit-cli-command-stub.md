# 0087 — Add `audit` CLI command stub

**Area:** cli-init

## Problem

The area spec lists `audit` as a CLI entry point, but it is not implemented. Running
`scriptorium audit` currently prints "unknown command" and exits with code 1.

## Requirements

- Add an `"audit"` case to the CLI argument parser in `src/scriptorium.nim`.
- The command should print `"scriptorium: audit not yet implemented"` to stdout and
  exit with code 0.
- Add `"audit"` to the `Usage` help string with a short description like
  `scriptorium audit             Audit plan branch health`.
- Add a test in `tests/integration_cli.nim` that runs `audit` and checks it exits
  with code 0 and prints the "not yet implemented" message.

## Key files

- `src/scriptorium.nim` — CLI entry point, `case args[0]` block and `Usage` constant
- `tests/integration_cli.nim` — integration tests for CLI commands
````
