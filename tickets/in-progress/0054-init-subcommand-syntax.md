# Change --init Flag To init Subcommand

**Area:** cli-init

## Problem

The current CLI uses `scriptorium --init [path]` flag syntax. The spec requires
`scriptorium init [path]` subcommand syntax instead.

## Requirements

- Add `init` as a subcommand in the CLI argument parser in `src/scriptorium.nim`.
- `scriptorium init` with no path argument defaults to the current directory.
- `scriptorium init <path>` initializes the given path.
- Remove or deprecate the `--init` flag.
- Update `--help` output to show `init` as a subcommand alongside `run`, `status`,
  `plan`, `ask`, and `worktrees`.
- Update all references to `--init` in code comments and log messages.

## Files To Change

- `src/scriptorium.nim` — CLI argument parsing.
- `src/scriptorium/init.nim` — if any flag-specific logic exists.
- `tests/integration_cli.nim` — update test to use `init` subcommand.

## Acceptance Criteria

- `scriptorium init` works as a subcommand.
- `scriptorium --init` no longer works (or prints a deprecation message).
- Existing tests pass with the new syntax.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0054-init-subcommand-syntax

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Straightforward CLI refactor in a single main file changing flag-based parsing to subcommand parsing, with minor test updates — low integration risk, one attempt expected.
