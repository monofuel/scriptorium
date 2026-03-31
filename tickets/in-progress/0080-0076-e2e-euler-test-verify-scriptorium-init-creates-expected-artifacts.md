# 0076 E2E Euler test: verify scriptorium init creates expected artifacts

**Area:** config-testing

**Depends:** 0075

## Summary

Per V11 §44, the E2E Euler test must verify that `scriptorium init` (called via `initLiveRepo`) actually created `AGENTS.md`, `Makefile`, and `scriptorium.json` before continuing with the orchestrator flow. This proves init produces a repo the orchestrator can run against without manual scaffolding.

## Requirements

1. In `tests/e2e_euler_live.nim`, after the `initLiveRepo(repoPath)` call and before `addEulerMakefile(repoPath)`, add assertions that verify:
   - `AGENTS.md` exists in `repoPath` and is non-empty.
   - `Makefile` exists in `repoPath` and is non-empty.
   - `scriptorium.json` exists in `repoPath`.
   - The `scriptorium/plan` branch exists (check via `git rev-parse --verify scriptorium/plan`).

2. These checks must use `doAssert` with clear failure messages (e.g., `"scriptorium init did not create AGENTS.md"`).

## Notes

- `initLiveRepo` already calls `scriptorium init` via the CLI binary. The test just needs explicit assertions that the artifacts exist.
- The test then continues to overwrite the Makefile with `addEulerMakefile` for the Euler-specific quality gates — that is expected and correct.
- Use `std/os` `fileExists` and `readFile` for the checks (already imported in the test).

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0080-0076-e2e-euler-test-verify-scriptorium-init-creates-expected-artifacts
