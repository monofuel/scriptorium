# Init Generates scriptorium.json

**Area:** cli-init

## Problem

`scriptorium init` does not generate a `scriptorium.json` config file. Users
must create one manually or rely on in-memory defaults.

## Requirements

- During init, check if `scriptorium.json` exists in the target repo root.
- If missing, generate it using `defaultConfig()` from `config.nim`, serialized
  to JSON.
- Leave the file uncommitted for user customization.
- Log that the file was created.

## Files To Change

- `src/scriptorium/init.nim` — add scriptorium.json generation step.
- `tests/integration_cli.nim` — verify scriptorium.json is created when missing.

## Acceptance Criteria

- Running `scriptorium init` on a repo without scriptorium.json creates one
  with default config values.
- Running `scriptorium init` on a repo that already has scriptorium.json skips this step.
- The generated JSON is valid and parseable by the config loader.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0058-init-generates-scriptorium-json
