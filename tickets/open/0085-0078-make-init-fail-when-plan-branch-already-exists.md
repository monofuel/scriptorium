# 0078 Make init fail when plan branch already exists

**Area:** cli-init

## Description

Per the area spec, `scriptorium init` should fail if the `scriptorium/plan` branch already exists. Currently init is idempotent — it silently skips plan branch creation if it exists. The new behavior should raise an error with a clear message like: `scriptorium/plan branch already exists — workspace is already initialized.`

Note: The default-branch artifact creation (AGENTS.md, Makefile, etc.) should remain idempotent — only the plan branch existence check should fail. This means if a user runs init, then deletes AGENTS.md and runs init again, it should fail because the plan branch exists. Users who need to re-scaffold files should do so manually.

## Tasks

1. In `src/scriptorium/init.nim` `runInit`, after the `planBranchExists` check (line 98), add:
   ```nim
   if planBranchExists:
     raise newException(ValueError, "scriptorium/plan branch already exists — workspace is already initialized")
   ```
2. Remove the idempotent logic that skips plan branch creation (the `if not planBranchExists:` guard is now redundant since we fail earlier).
3. Remove the "already initialized, nothing to do" output path (line 167-168).
4. Update `tests/test_init.nim`:
   - `testAlreadyInitializedDoesNotCrash` → rename to `testAlreadyInitializedFails` and assert it raises `ValueError`.
   - `testDoubleInitIdempotent` → update to assert the second init raises `ValueError`.
5. Update `tests/integration_cli.nim` if any tests rely on double-init succeeding.
6. Run `make test` to confirm.
