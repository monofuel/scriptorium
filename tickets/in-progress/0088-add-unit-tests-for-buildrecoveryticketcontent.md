# Add unit tests for buildRecoveryTicketContent

**Area:** agent-execution

The `buildRecoveryTicketContent` proc in `src/scriptorium/recovery.nim` (line 309) generates the markdown content for recovery tickets created when main branch tests fail. It handles test output truncation at `MaxRecoveryTestOutputChars = 8000` characters and produces a specific markdown structure. This function has zero test coverage.

Create `tests/test_recovery.nim` with unit tests covering:

- Output contains the expected title (`# Recovery: Fix Failing Tests on Main Branch`).
- Output contains `**Area:** recovery`.
- Output contains the provided commit hash.
- Output includes the test output in a fenced code block under `## Test Failure Output`.
- Test output longer than 8000 characters is truncated with `(output truncated)` marker.
- Test output exactly at 8000 characters is not truncated.
- Empty test output produces a fallback message about running `make test` and `make integration-test`.
- The commit hash appears in the description text.

This is a pure function test — construct test inputs directly, no mocks or git operations needed.

Relevant source: `src/scriptorium/recovery.nim` lines 309–324.
Constant: `MaxRecoveryTestOutputChars = 8000`.
Import needed: `scriptorium/recovery`.

Note: `buildRecoveryTicketContent` is not exported (no `*` suffix). Either add `*` to export it for testing, or if the project prefers testing unexported procs, use `include` instead of `import` in the test file. Check `tests/config.nims` for the `--path` setting that enables direct imports.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0088-add-unit-tests-for-buildrecoveryticketcontent
