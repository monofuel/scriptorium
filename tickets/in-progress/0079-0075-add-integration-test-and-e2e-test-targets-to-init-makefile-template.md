# 0075 Add integration-test and e2e-test targets to init Makefile template

**Area:** config-testing

## Summary

The `scriptorium init` command creates a starter Makefile with only `test` and `build` targets. Per V11 §35, all managed projects must also have `integration-test` and optionally `e2e-test` make targets.

## Requirements

1. In `src/scriptorium/init.nim`, update the `MakefileTemplate` constant to include:
   - `integration-test` target (with placeholder `@echo "no integration tests configured"`).
   - `e2e-test` target (with placeholder `@echo "no e2e tests configured"`).
   - Add all four targets to the `.PHONY` declaration.

2. In `tests/test_init.nim`, add or update a test that verifies the Makefile created by `runInit` contains all four required targets: `test`, `build`, `integration-test`, `e2e-test`.

## Notes

- The Makefile template is a `const` string in init.nim. Just extend it with the new targets.
- Keep the template minimal — placeholder echo commands only.
- Existing repos that already ran init will not be affected (init skips files that already exist).

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0079-0075-add-integration-test-and-e2e-test-targets-to-init-makefile-template
