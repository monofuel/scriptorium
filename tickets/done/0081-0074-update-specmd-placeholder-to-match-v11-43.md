# 0074 Update spec.md placeholder to match V11 §43

**Area:** cli-init

## Description

The `SpecPlaceholder` constant in `src/scriptorium/init.nim` needs updating to match the V11 §43 spec.

**Current:**
```
# Spec

Run `scriptorium plan` to build your spec with the Architect.
```

**Required:**
```
# Spec

This is a new project. See AGENTS.md for project conventions.

Run `scriptorium plan` to build your spec with the Architect.
```

## Tasks

1. Update the `SpecPlaceholder` constant in `src/scriptorium/init.nim` (line 8) to include the new line.
2. Update the `SpecPlaceholder` constant in `tests/test_init.nim` (line 6) to match.
3. Update `tests/integration_cli.nim` test "init spec.md references AGENTS.md" — it already checks for `AGENTS.md` in spec content, so it should still pass, but verify.
4. Run `make test` to confirm all init tests pass.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0081-0074-update-specmd-placeholder-to-match-v11-43

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 10
- reasoning: Simple string constant update in two files with a verification pass on an existing integration test, single attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0081/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0081/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Updated the `SpecPlaceholder` constant in both `src/scriptorium/init.nim` and `tests/test_init.nim` to include the new "This is a new project. See AGENTS.md for project conventions." line. All tests pass, including the integration test that verifies spec.md references AGENTS.md.
```

### Agent Stdout Tail
```text
type":"result","subtype":"success","is_error":false,"duration_ms":49403,"duration_api_ms":43663,"num_turns":14,"result":"Done. Updated the `SpecPlaceholder` constant in both `src/scriptorium/init.nim` and `tests/test_init.nim` to include the new \"This is a new project. See AGENTS.md for project conventions.\" line. All tests pass, including the integration test that verifies spec.md references AGENTS.md.","stop_reason":"end_turn","session_id":"359d1aa6-ebef-4ce0-9955-843768eafd2c","total_cost_usd":0.24002924999999994,"usage":{"input_tokens":13,"cache_creation_input_tokens":14823,"cache_read_input_tokens":194141,"output_tokens":2010,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":14823,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":13,"outputTokens":2010,"cacheReadInputTokens":194141,"cacheCreationInputTokens":14823,"webSearchRequests":0,"costUSD":0.24002924999999994,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"2cd4a206-fd78-4b8b-ba6b-899df849cae4"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 21s

**Review Reasoning:** I need to verify the `submit_review` MCP tool is available, then review the diff.


The diff is minimal and correct. Let me verify against all review criteria:

**Ticket requirements:** Both files updated (`src/scriptorium/init.nim` and `tests/test_init.nim`), agent confirmed tests pass. All 4 tasks complete.

**Spec compliance (V11 §43):** The new constant produces exactly:
```
# Spec

This is a new project. See AGENTS.md for project conventions.

Run `scriptorium plan` to build your spec with the Architect.
```
This matches the spec verbatim.

**Convention enforcement:** Only string constant values changed. No new procs, imports, or variables — nothing to flag.

**Code quality:** Clean, minimal change. No dead code, no unrelated changes, no leftover artifacts.
Approved. The change is a straightforward, spec-compliant string constant update in both source and test files.

## Merge Queue Success
- Summary: Updated SpecPlaceholder constant in src/scriptorium/init.nim and tests/test_init.nim to include "This is a new project. See AGENTS.md for project conventions." line per V11 §43. All tests pass.\n
### Quality Check Output
```text
nim/integration_merge_queue_d/@pstd@sprivate@sospaths2.nim.c:1474:1: fatal error: error writing to /dev/shm/cc0VnEov.s: No space left on device
[tests/integration_merge_queue.nim]  1474 | }
[tests/integration_merge_queue.nim]       | ^
[tests/integration_merge_queue.nim] compilation terminated.
[tests/integration_merge_queue.nim] /home/scriptorium/.cache/nim/integration_merge_queue_d/@pjson.nim.c:2795:1: fatal error: error writing to /dev/shm/cc6pXPGu.s: No space left on device
[tests/integration_merge_queue.nim]  2795 | }
[tests/integration_merge_queue.nim]       | ^
[tests/integration_merge_queue.nim] compilation terminated.
[tests/integration_merge_queue.nim] /home/scriptorium/.cache/nim/integration_merge_queue_d/@ptimes.nim.c:3707:1: fatal error: error writing to /dev/shm/ccGZyRxn.s: No space left on device
[tests/integration_merge_queue.nim]  3707 | }
[tests/integration_merge_queue.nim]       | ^
[tests/integration_merge_queue.nim] compilation terminated.
[tests/integration_merge_queue.nim] /home/scriptorium/.cache/nim/integration_merge_queue_d/@pstrutils.nim.c:3311:1: fatal error: error writing to /dev/shm/cc0Rfras.s: No space left on device
[tests/integration_merge_queue.nim]  3311 | }
[tests/integration_merge_queue.nim]       | ^
[tests/integration_merge_queue.nim] compilation terminated.
[tests/integration_merge_queue.nim] /home/scriptorium/.cache/nim/integration_merge_queue_d/@ptables.nim.c:7831:1: fatal error: error writing to /dev/shm/ccIK5mNi.s: No space left on device
[tests/integration_merge_queue.nim]  7831 | }
[tests/integration_merge_queue.nim]       | ^
[tests/integration_merge_queue.nim] compilation terminated.
[tests/integration_merge_queue.nim] /home/scriptorium/.cache/nim/integration_merge_queue_d/@psystem.nim.c:12144:1: fatal error: error writing to /dev/shm/ccPS0EOk.s: No space left on device
[tests/integration_merge_queue.nim] 12144 | }
[tests/integration_merge_queue.nim]       | ^
[tests/integration_merge_queue.nim] compilation terminated.
```

## Metrics
- wall_time_seconds: 143
- coding_wall_seconds: 50
- test_wall_seconds: 15
- attempt_count: 1
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 85104

## Post-Analysis
- actual_difficulty: trivial
- prediction_accuracy: overestimated
- brief_summary: Predicted easy, actual was trivial with 1 attempt(s) in 2m23s.
