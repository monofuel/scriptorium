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

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0085-0078-make-init-fail-when-plan-branch-already-exists

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 11
- reasoning: Straightforward guard clause addition in one source file plus updating two existing test cases to expect errors instead of success, minimal integration risk.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0085/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0085/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changes:

- **`src/scriptorium/init.nim`**: Added early `ValueError` raise when `planBranchExists` is true. Removed the `if not planBranchExists:` guard around plan branch creation and the "already initialized, nothing to do" output path.
- **`tests/test_init.nim`**: Renamed `testAlreadyInitializedDoesNotCrash` → `testAlreadyInitializedFails` and `testDoubleInitIdempotent` → `testDoubleInitFails`, both now assert `ValueError` is raised.
```

### Agent Stdout Tail
```text
it.nim`**: Added early `ValueError` raise when `planBranchExists` is true. Removed the `if not planBranchExists:` guard around plan branch creation and the \"already initialized, nothing to do\" output path.\n- **`tests/test_init.nim`**: Renamed `testAlreadyInitializedDoesNotCrash` → `testAlreadyInitializedFails` and `testDoubleInitIdempotent` → `testDoubleInitFails`, both now assert `ValueError` is raised.","stop_reason":"end_turn","session_id":"57b32f01-a39c-4c31-9a7d-3fc0660f5bed","total_cost_usd":0.541819,"usage":{"input_tokens":21,"cache_creation_input_tokens":30714,"cache_read_input_tokens":436053,"output_tokens":5269,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":30714},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":21,"outputTokens":5269,"cacheReadInputTokens":436053,"cacheCreationInputTokens":30714,"webSearchRequests":0,"costUSD":0.541819,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"8ac5a573-62d8-4539-8003-f848386e5088"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 1m1s

**Review Reasoning:** Let me check if there are integration tests that reference double-init or the old behavior.
Let me check the integration test that references "already initialized":
Good — the integration test at line 35 already expects `ValueError` on double init. Now let me verify the source changes more carefully.
The changes look clean and correct. Let me verify the output section at the end of the file to check for any issues with the indentation change.
Everything looks correct. The changes are minimal, focused, and match the ticket requirements exactly. Let me verify the test file is complete and well-formed.
All changes are correct and well-structured. The implementation:

1. **Matches the ticket** — adds the early `ValueError` raise, removes the idempotent guard, removes the "nothing to do" output path.
2. **Matches the spec** — Section 1 says init must "fail if `scriptorium/plan` already exists".
3. **Follows conventions** — doc comments are complete sentences with punctuation, no convention violations in naming or style.
4. **Tests are correct** — both renamed tests properly assert `ValueError` is raised.
5. **Integration tests are fine** — `integration_scriptorium.nim:35` already expects `ValueError` on double init.
6. **No dead code, no unrelated changes, no leftover artifacts.**
Approved. The changes are minimal, correct, and fully aligned with the ticket requirements and spec. The early `ValueError` guard replaces the idempotent behavior cleanly, and both unit and integration tests correctly assert the new error behavior.
