# 0092 — Add reasoning-effort support to typoi harness

**Area:** harness-backends
**Priority:** low

## Problem

The codex and claude-code harnesses both support reasoning-effort normalization and pass it as a CLI argument. The typoi harness does not: `TypoiRunRequest` has no `reasoningEffort` field, `agent_runner.nim` does not pass reasoning effort for the typoi backend, and `buildTypoiExecArgs` does not emit a reasoning-effort flag.

## Task

1. Add a `reasoningEffort*: string` field to `TypoiRunRequest` in `src/scriptorium/harness_typoi.nim`.

2. In `buildTypoiExecArgs`, if `request.reasoningEffort` is non-empty, add `--reasoning-effort` and the normalized value to the args list. Typoi accepts the values `low`, `medium`, `high` (same as claude-code). No `xhigh` mapping is needed.

3. In `src/scriptorium/agent_runner.nim`, in the `harnessTypoi` branch of `runAgent`, pass `reasoningEffort: request.reasoningEffort` to `TypoiRunRequest` (currently missing).

4. Add unit tests in `tests/test_harness_typoi.nim`:
   - `buildTypoiExecArgs` with `reasoningEffort = "high"` includes `--reasoning-effort high` in the output.
   - `buildTypoiExecArgs` with empty `reasoningEffort` does not include `--reasoning-effort` in the output.

Use `jsony` for JSON parsing (already in use).

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0103-0092-add-reasoning-effort-support-to-typoi-harness
