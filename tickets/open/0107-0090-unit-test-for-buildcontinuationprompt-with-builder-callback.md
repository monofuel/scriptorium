# 0090 — Unit test for buildContinuationPrompt with builder callback

**Area:** compaction-context

**File:** `tickets/open/0090-test-continuation-builder.md`

## Problem

The `buildContinuationPrompt` function in all three harnesses supports a `ContinuationPromptBuilder` callback, but there are no tests verifying this code path. Since ticket 0088 will start setting the builder, we need test coverage to prevent regressions.

## Task

Add unit tests in `tests/test_continuation.nim` (or an appropriate existing test file) that:

1. Call `buildContinuationPrompt` from `harness_claude_code` with a non-nil `builder` proc and a `workingDir`, and verify the builder's output appears in the resulting prompt.
2. Call `buildContinuationPrompt` with a nil builder and verify it falls back to the default continuation text.
3. Call `buildContinuationPrompt` with a nil builder but a non-empty `customContinuationPrompt` and verify the custom text is used.

Ensure `tests/config.nims` is respected (it adds `--path:"../src"` so test files can import project modules directly).

## Verification

- `nim r tests/test_continuation.nim` passes (or whichever file the tests are added to).
- `make test` passes.
