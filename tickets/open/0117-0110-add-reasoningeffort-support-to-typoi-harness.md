# 0110 — Add reasoningEffort support to typoi harness

**Area:** harness-backends

## Problem

The typoi harness (`src/scriptorium/harness_typoi.nim`) lacks a `reasoningEffort` field on `TypoiRunRequest`. The agent runner (`agent_runner.nim` lines 189–210) does not pass `reasoningEffort` for the typoi backend, even though it does for codex and claude-code.

If a user configures `reasoningEffort` on a role that routes to typoi (e.g., a non-claude, non-codex model), the setting is silently dropped.

## Changes

1. **`src/scriptorium/harness_typoi.nim`**:
   - Add `reasoningEffort*: string` to `TypoiRunRequest`.
   - In `buildTypoiExecArgs`, if `request.reasoningEffort` is non-empty, add `--reasoning-effort` and the value to the argument list (typoi CLI supports this flag).

2. **`src/scriptorium/agent_runner.nim`**:
   - In the `harnessTypoi` branch of `runAgent`, add `reasoningEffort: request.reasoningEffort,` to the `TypoiRunRequest` constructor.

3. **`tests/test_harness_typoi.nim`**:
   - Add a unit test for `buildTypoiExecArgs` that verifies `--reasoning-effort high` appears in the args when `reasoningEffort` is set to `"high"`.
   - Add a test that verifies the flag is absent when `reasoningEffort` is empty.

## Validation

- `make test` passes with the new typoi reasoning effort tests.
