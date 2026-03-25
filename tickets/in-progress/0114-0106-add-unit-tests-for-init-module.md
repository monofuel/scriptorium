# 0106 Add unit tests for init module

**Area:** cli-init

## Problem

No unit tests exist for `src/scriptorium/init.nim`. The init flow has several validation paths and creates specific directory structures that should be tested.

## Task

Create `tests/test_init.nim` with unit tests covering:

1. **Not a git repo** — calling `runInit` on a non-git directory raises `ValueError`.
2. **Already initialized** — calling `runInit` on a repo that already has a `scriptorium/plan` branch raises `ValueError`.
3. **Successful init** — calling `runInit` on a fresh git repo (create a temp repo with `git init`):
   - Creates the `scriptorium/plan` branch.
   - The plan branch contains `areas/`, `tickets/open/`, `tickets/in-progress/`, `tickets/done/`, `tickets/stuck/`, `decisions/` directories (each with `.gitkeep`).
   - The plan branch contains `spec.md` with the correct placeholder text.
4. **spec.md placeholder content** — verify the exact text matches the spec requirement.

Use `std/tempfiles` or `std/os` to create temporary directories for test repos. Clean up after each test. Use `osproc` to run `git init` in temp dirs. Import `runInit` from `scriptorium/init`. Pass `quiet = true` to suppress output.

The test file must have `--path:"../src"` available via `tests/config.nims` (already exists).

## Files

- `tests/test_init.nim` (new)

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0114-0106-add-unit-tests-for-init-module
