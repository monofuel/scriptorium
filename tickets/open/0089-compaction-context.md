**ID:** 0077
**Title:** Add unit tests for continuation prompt builder with AGENTS.md injection
**Area:** compaction-context
**Depends:** 0074, 0075

**Description:**

Add integration-level unit tests to `tests/test_scriptorium.nim` that verify the full continuation prompt pipeline works with the AGENTS.md builder:

1. **Builder priority test**: Create a mock `AgentRunRequest` with both `continuationPrompt` (static string) and `continuationPromptBuilder` set. Verify the builder output takes priority over the static string. This tests the priority logic in `buildContinuationPrompt` (`src/scriptorium/harness_claude_code.nim:426`).

2. **Builder nil fallback test**: Create a request with `continuationPromptBuilder` set to `nil` and a `continuationPrompt` string. Verify the static string is used as fallback.

3. **Empty builder output test**: Create a builder that returns `""`. Verify the static `continuationPrompt` is used as fallback (matching the `builtText.len > 0` check at line 426).

Import `buildContinuationPrompt` from `harness_claude_code` (it may need to be exported with `*` — if so, add the export). Construct minimal `ClaudeCodeRunResult` objects for the `previousResult` parameter.

**Verify:** `make test` passes with the new tests.
````
