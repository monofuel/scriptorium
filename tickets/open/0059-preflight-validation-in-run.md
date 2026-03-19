# Pre-Flight Validation In scriptorium run

**Area:** cli-init

## Problem

`scriptorium run` has no pre-flight checks. If required files or branches are
missing, the orchestrator silently waits or fails with unclear errors.

## Requirements

- Before starting the orchestrator loop, validate:
  1. `scriptorium/plan` branch exists.
  2. `AGENTS.md` exists in the repo root.
  3. `Makefile` exists in the repo root.
  4. Required make targets exist (at minimum `test`).
  5. Agent binary is available (e.g., `codex` or configured harness binary).
  6. Agent auth is configured (check for API keys or credential files).
- On failure, print a clear error message explaining what is missing and how
  to fix it (e.g., "Run `scriptorium init` first").
- Exit with non-zero status on validation failure.

## Files To Change

- `src/scriptorium.nim` or `src/scriptorium/orchestrator.nim` — add pre-flight checks.
- `tests/integration_cli.nim` or new test — verify validation errors.

## Acceptance Criteria

- `scriptorium run` exits with a clear error if plan branch is missing.
- `scriptorium run` exits with a clear error if AGENTS.md is missing.
- `scriptorium run` exits with a clear error if Makefile or required targets are missing.
- `scriptorium run` warns or errors if agent binary/auth is not found.
