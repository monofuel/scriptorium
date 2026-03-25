# 0106 Add unit tests for init module

**Area:** cli-init

## Problem

No unit tests exist for `src/scriptorium/init.nim`. The init flow has several validation paths and creates specific directory structures that should be tested.

## Task

Create `tests/test_init.nim` with unit tests covering:

1. **Not a git repo** — calling `runInit` on a non-git directory raises `ValueError`.
2. **Already initialized** — calling `runInit` on a repo that already has a `scriptorium/plan` branch raises `ValueError`.
3. **Successful init** — calling `runInit` on a fresh git repo (create a temp repo with `git init`):
   - Creates the `scriptorium/plan` branch.
   - The plan branch contains `areas/`, `tickets/open/`, `tickets/in-progress/`, `tickets/done/`, `tickets/stuck/`, `decisions/` directories (each with `.gitkeep`).
   - The plan branch contains `spec.md` with the correct placeholder text.
4. **spec.md placeholder content** — verify the exact text matches the spec requirement.

Use `std/tempfiles` or `std/os` to create temporary directories for test repos. Clean up after each test. Use `osproc` to run `git init` in temp dirs. Import `runInit` from `scriptorium/init`. Pass `quiet = true` to suppress output.

The test file must have `--path:"../src"` available via `tests/config.nims` (already exists).

## Files

- `tests/test_init.nim` (new)

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0114-0106-add-unit-tests-for-init-module

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Single new test file but requires setting up temp git repos, running git commands via osproc, and verifying directory structures and file contents across multiple test cases — moderate complexity with possible git subprocess quirks requiring a retry.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0114/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0114/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Created `tests/test_init.nim` with 4 tests covering all cases from the ticket:

1. **Not a git repo** — `runInit` raises `ValueError` on a plain directory
2. **Already initialized** — `runInit` raises `ValueError` when `scriptorium/plan` branch exists
3. **Successful init** — verifies plan branch creation, all 6 directories with `.gitkeep`, and `spec.md` presence
4. **spec.md placeholder content** — verifies exact text matches the constant
```

### Agent Stdout Tail
```text
ering all cases from the ticket:\n\n1. **Not a git repo** — `runInit` raises `ValueError` on a plain directory\n2. **Already initialized** — `runInit` raises `ValueError` when `scriptorium/plan` branch exists\n3. **Successful init** — verifies plan branch creation, all 6 directories with `.gitkeep`, and `spec.md` presence\n4. **spec.md placeholder content** — verifies exact text matches the constant","stop_reason":"end_turn","session_id":"dc86ba6e-a900-4421-8431-05bd44b858f6","total_cost_usd":0.39153625,"usage":{"input_tokens":55,"cache_creation_input_tokens":32173,"cache_read_input_tokens":232660,"output_tokens":2954,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":32173},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":55,"outputTokens":2954,"cacheReadInputTokens":232660,"cacheCreationInputTokens":32173,"webSearchRequests":0,"costUSD":0.39153625,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"b5c1e3a2-d926-4264-b77d-0e8f6b63554d"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 1m5s

**Review Reasoning:** I'll review the diff against the ticket requirements and project conventions.
Let me check the source files to verify the test correctness.
The test file looks solid. Let me verify one more thing about the project's test patterns.
The review is complete. Here's my assessment:

**Convention compliance**: All good.
- Single import block with bracket syntax, std/ first then local
- PascalCase constants, grouped const block
- Doc comments (`##`) on every proc, complete sentences with punctuation
- `when isMainModule` pattern matches other test files in the project

**Spec compliance**: All 4 required test cases are present and correctly implemented per the ticket.

**Code quality**: Clean, no dead code, no unused imports (`strutils` is used for `strip` and `join`), no leftover artifacts.

**Minor note**: The `execCmdEx` calls in `testSuccessfulInit` use unquoted string concatenation for paths (e.g., `"git -C " & repo & " ..."`), whereas the source code uses `quoteShell`. This is safe here since temp paths won't contain spaces, but it's a small inconsistency. Not worth blocking on.
Approved. The test file covers all four ticket requirements correctly, follows project conventions, and matches the actual behavior of `runInit` in `src/scriptorium/init.nim`.

## Merge Queue Failure
- Summary: Add tests/test_init.nim with 4 unit tests for the init module: non-git directory raises ValueError, already-initialized repo raises ValueError, successful init creates plan branch with expected directory structure and .gitkeep files, and spec.md placeholder content matches exactly.\n- Failed gate: make test\n
### Merge Output
```text
Current branch scriptorium/ticket-0114 is up to date.
```

### Quality Check Output
```text
$ make test
nimby sync -g nimby.lock
Nimby 0.1.20
Using global packages directory.
Nimby is already running, delete ~/.nimby/nimbylock to release lock
make: *** [Makefile:7: nim.cfg] Error 1
```

## Metrics
- wall_time_seconds: 146
- coding_wall_seconds: 74
- test_wall_seconds: 0
- attempt_count: 1
- outcome: reopened
- failure_reason: test_failure
- model: claude-opus-4-6
- stdout_bytes: 105936

## Post-Analysis
- actual_difficulty: hard
- prediction_accuracy: underestimated
- brief_summary: Predicted medium, actual was hard with 1 attempt(s) in 2m26s.

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Single new test file requiring temp git repo setup and subprocess calls — moderate complexity, but the merge queue failure was due to a nimby lock issue (infrastructure), not code complexity, so the retry should succeed quickly.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0114/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0114/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Created `tests/test_init.nim` with 4 passing tests:

1. **Not a git repo** — `runInit` raises `ValueError` on a plain directory
2. **Already initialized** — `runInit` raises `ValueError` when `scriptorium/plan` branch exists
3. **Successful init** — verifies plan branch creation, all 6 directories with `.gitkeep`, and `spec.md` presence
4. **spec.md placeholder content** — verifies exact text matches the constant
```

### Agent Stdout Tail
```text
ing tests:\n\n1. **Not a git repo** — `runInit` raises `ValueError` on a plain directory\n2. **Already initialized** — `runInit` raises `ValueError` when `scriptorium/plan` branch exists\n3. **Successful init** — verifies plan branch creation, all 6 directories with `.gitkeep`, and `spec.md` presence\n4. **spec.md placeholder content** — verifies exact text matches the constant","stop_reason":"end_turn","session_id":"12dad0b9-5e43-462d-ba79-b89e8cc88dba","total_cost_usd":0.42936199999999997,"usage":{"input_tokens":5746,"cache_creation_input_tokens":29090,"cache_read_input_tokens":269989,"output_tokens":3353,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":29090},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":5746,"outputTokens":3353,"cacheReadInputTokens":269989,"cacheCreationInputTokens":29090,"webSearchRequests":0,"costUSD":0.42936199999999997,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"f4a30e64-0544-4269-a3f2-1b369f1bea19"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 31s

**Review Reasoning:** I'll review the diff against the ticket requirements and project conventions.
Let me verify the test against the source module.
Now I have full context. Let me review:

**Ticket requirements:**
1. Not a git repo → raises ValueError ✅
2. Already initialized → raises ValueError ✅
3. Successful init → plan branch, directories with .gitkeep, spec.md ✅
4. spec.md placeholder content matches ✅

**Convention check:**
- Import: single block, bracket syntax, std/ first then local ✅
- Constants: PascalCase, grouped `const` block ✅
- Doc comments (`##`) on every proc, complete sentences with punctuation ✅
- No forward declarations ✅
- `quoteShell` used for paths (improvement over first attempt) ✅

**Spec compliance:**
- The test's `SpecPlaceholder` matches `init.nim:8` exactly ✅
- The test's `ExpectedDirs` matches `init.nim:16-23` (`PlanDirs`) exactly ✅
- The spec's required `tickets/stuck/` directory is present ✅ (note: spec §1 doesn't list `tickets/stuck/` but the code does, and the ticket says to test what `runInit` creates)

**Code quality:**
- No dead code, no unused imports (`strutils` used for `strip` and `join`) ✅
- No leftover artifacts ✅
- No unrelated changes ✅
- `when isMainModule` pattern matches project conventions ✅

**One minor note:** `createTempRepo` doesn't use `quoteShell` for the `git init` command (line `"git init " & quoteShell(result)`), wait — actually it does use `quoteShell`. All `execCmdEx` calls use `quoteShell`. Good.

Everything looks clean. The test file correctly covers all four ticket requirements, follows project conventions, and matches the source module's behavior.


Review approved. The test file correctly covers all four ticket requirements, follows all project conventions (imports, naming, doc comments, variable grouping), and the constants match the source module exactly.
