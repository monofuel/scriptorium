# 0103-extract-shared-harness-utilities

**Area:** harness-backends

## Summary

Extract duplicated utility functions from the three harness files into a shared module to eliminate copy-paste and reduce maintenance burden.

## Context

The following functions are copy-pasted identically (or near-identically) across `harness_codex.nim`, `harness_claude_code.nim`, and `harness_typoi.nim`:

- `sanitizePathSegment` — path sanitization for log directories
- `truncateTail` — tail extraction for continuation prompts
- `elapsedMs` — MonoTime elapsed helper
- `waitForReadable` — POSIX fd select wrapper (only error message string differs)
- `readOutputChunk` — POSIX fd read wrapper (only error message string differs)
- `buildContinuationPrompt` — retry prompt assembly (structurally identical, only result type differs)

## Requirements

1. Create `src/scriptorium/harness_common.nim` with these shared utilities extracted.
2. For `waitForReadable` and `readOutputChunk`, parameterize the error message label (e.g. accept a `label: string` parameter) to preserve the harness-specific error context.
3. For `buildContinuationPrompt`, make a generic version that accepts the needed fields (attempt, exitCode, timeoutKind as string, lastMessage, stdout) rather than a harness-specific result type.
4. Update all three harness files to import from `harness_common` and remove their local copies.
5. Run `make test` to verify nothing breaks.

## Notes

- The project uses Nim. Follow the import style in AGENTS.md: one `import` block, bracket syntax, std/ then libs then local.
- `waitForReadable` and `readOutputChunk` use `std/[posix, os, strformat]`.
- `buildContinuationPrompt` uses `./prompt_catalog` for `CodexRetryContinuationTemplate` and `CodexRetryDefaultContinuationText`.
- Keep `common.nim` for the `ContinuationPromptBuilder` type — the new file is `harness_common.nim` for harness-level shared code.
