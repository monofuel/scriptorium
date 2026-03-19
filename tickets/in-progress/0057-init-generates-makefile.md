# Init Generates Starter Makefile

**Area:** cli-init

## Problem

`scriptorium init` does not generate a Makefile. The orchestrator expects
`make test` and other targets to exist, so new projects fail at runtime.

## Requirements

- During init, check if a `Makefile` exists in the target repo root.
- If missing, generate a minimal Makefile with placeholder targets:
  - `test` — placeholder that echoes "no tests configured".
  - `build` — placeholder that echoes "no build configured".
  - Any other targets the orchestrator expects.
- Leave the Makefile uncommitted (or commit on default branch) for user customization.
- Log that the Makefile was created.

## Files To Change

- `src/scriptorium/init.nim` — add Makefile generation step.
- `tests/integration_cli.nim` — verify Makefile is created when missing.

## Acceptance Criteria

- Running `scriptorium init` on a repo without a Makefile creates one with placeholder targets.
- Running `scriptorium init` on a repo that already has a Makefile skips this step.
- Generated Makefile has `test` and `build` targets at minimum.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0057-init-generates-makefile

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 11
- reasoning: Single-file addition of Makefile generation logic in init.nim following the existing pattern for AGENTS.md generation, plus a straightforward integration test — minimal complexity, one attempt expected.
