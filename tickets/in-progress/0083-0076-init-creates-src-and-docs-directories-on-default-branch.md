# 0076 Init creates src/ and docs/ directories on default branch

**Area:** cli-init

## Description

Per V11 §35 (Project Opinions), scriptorium requires `src/`, `tests/`, `docs/` directories. Init already creates `tests/` (via `tests/config.nims`), but does not create `src/` or `docs/`. Init should create these directories with `.gitkeep` files and commit them if they don't already exist.

Existing directories must not be overwritten (same idempotent pattern as AGENTS.md and Makefile).

## Tasks

1. In `src/scriptorium/init.nim`, after the Makefile creation block and before the `scriptorium.json` creation block, add logic to:
   - Check if `src/` exists; if not, create it with a `.gitkeep`, `git add`, and commit.
   - Check if `docs/` exists; if not, create it with a `.gitkeep`, `git add`, and commit.
2. Track `createdSrc` and `createdDocs` booleans for the post-init output.
3. Include these in the "Created" output section and update the "already initialized" check.
4. Add a unit test in `tests/test_init.nim` verifying `src/.gitkeep` and `docs/.gitkeep` exist after init.
5. Add integration tests in `tests/integration_cli.nim` verifying:
   - Init creates `src/` and `docs/` directories.
   - Init skips them if they already exist.
6. Run `make test` to confirm.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0083-0076-init-creates-src-and-docs-directories-on-default-branch
