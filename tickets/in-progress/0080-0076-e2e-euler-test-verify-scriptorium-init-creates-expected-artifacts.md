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

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 10
- reasoning: Single-file change adding 4-5 doAssert lines in an existing test file using already-imported utilities, minimal logic complexity.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0080/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0080/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Added 4 assertion groups after `initLiveRepo(repoPath)` in `tests/e2e_euler_live.nim`:
- `AGENTS.md` exists and is non-empty
- `Makefile` exists and is non-empty
- `scriptorium.json` exists
- `scriptorium/plan` branch exists (via `git rev-parse --verify`)
```

### Agent Stdout Tail
```text
d":"78dbfa54-87f8-40b7-bca6-9d9bb3d769c9"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":26881,"duration_api_ms":26804,"num_turns":7,"result":"Done. Added 4 assertion groups after `initLiveRepo(repoPath)` in `tests/e2e_euler_live.nim`:\n- `AGENTS.md` exists and is non-empty\n- `Makefile` exists and is non-empty\n- `scriptorium.json` exists\n- `scriptorium/plan` branch exists (via `git rev-parse --verify`)","stop_reason":"end_turn","session_id":"c4f1cef1-10dc-4074-a52c-e2f6bc2f787f","total_cost_usd":0.1608455,"usage":{"input_tokens":9,"cache_creation_input_tokens":12096,"cache_read_input_tokens":106151,"output_tokens":1285,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":12096,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":9,"outputTokens":1285,"cacheReadInputTokens":106151,"cacheCreationInputTokens":12096,"webSearchRequests":0,"costUSD":0.1608455,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"daff1ecd-097b-4c0e-a7de-5cd8e32c9674"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 29s

**Review Reasoning:** Looking at the diff, I need to verify one thing about imports before submitting my review.
Good — `osproc` (for `execCmdEx`) and `os` (for `fileExists`, `readFile`, `/`, `quoteShell`) are already imported. No new imports needed.

The diff is clean, minimal, and matches all ticket requirements exactly:

1. `AGENTS.md` exists and non-empty — checked with `fileExists` + `readFile().len > 0` with clear `doAssert` messages.
2. `Makefile` exists and non-empty — same pattern.
3. `scriptorium.json` exists — checked with `fileExists`.
4. `scriptorium/plan` branch exists — checked via `git rev-parse --verify` using `execCmdEx`.
5. Assertions placed after `initLiveRepo` and before `addEulerMakefile` — correct position.
6. Uses `doAssert` with descriptive failure messages — all present and clear.

No convention violations: camelCase variables, no new procs needing doc comments, no unused imports, no dead code. The `##` comment is acceptable as a section marker within the test body.
Approved. The change is minimal, correct, and satisfies all ticket requirements. No convention violations or spec contradictions.
