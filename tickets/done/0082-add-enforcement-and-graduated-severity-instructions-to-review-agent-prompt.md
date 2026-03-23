<!-- ticket: 0076-review-prompt-enforcement-instructions.md -->
# Add enforcement and graduated severity instructions to review agent prompt

**Area:** review-agent
**Depends:** 0075

## Problem

The review agent prompt's `## Instructions` section is minimal — it only says to approve or request changes based on ticket requirements. Per the spec (Section 9), the prompt must include explicit instructions for:
- Enforcing `AGENTS.md` conventions (naming, logging, error handling, file organization).
- Enforcing `spec.md` compliance (implementation matches spec, no contradictions).
- Flagging code quality issues (unreachable code, unused imports, leftover artifacts, unrelated changes).
- Graduated severity (minor issues → approve with warnings; substantive violations → request changes).

## Requirements

1. **Update prompt template** (`src/scriptorium/prompts/review_agent.md`):
   - Replace the current `## Instructions` section with detailed enforcement instructions. The new instructions should cover:
     - **Convention enforcement:** Check the diff against `AGENTS.md` rules — naming conventions, import style, error handling patterns, comment style, variable grouping. Flag violations.
     - **Spec compliance:** Check that the implementation matches the spec section provided. Flag contradictions or missing required behavior.
     - **Code quality:** Flag unreachable code, unused imports introduced by the PR, leftover artifacts (commented-out code, TODO comments for completed work, assigned-but-unread variables), and changes unrelated to the ticket goal (but don't be aggressive about legitimate incidental fixes).
     - **Graduated severity:**
       - Minor style issues and small convention deviations → use `approve_with_warnings` with warnings describing the issues.
       - Substantive violations (wrong behavior, spec contradictions, convention violations affecting correctness, dead code, unrelated changes) → use `request_changes` with clear feedback.
     - Keep the instruction that `submit_review` must be called exactly once.
     - Keep the CRITICAL instruction about verifying the tool is available.

2. **No code changes needed** — this is a prompt-only change. The template placeholders are unchanged.

3. **Tests**: Verify the prompt template still renders correctly with existing tests (no new placeholders introduced).

## Key files
- `src/scriptorium/prompts/review_agent.md` — prompt template (only file to modify)

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0082-add-enforcement-and-graduated-severity-instructions-to-review-agent-prompt

## Prediction
- predicted_difficulty: trivial
- predicted_duration_minutes: 5
- reasoning: Prompt-only change to a single markdown template file, replacing one section of text with more detailed instructions, no code or logic changes needed.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0082/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0082/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Updated `src/scriptorium/prompts/review_agent.md` with detailed enforcement instructions covering:
- **Convention enforcement** — naming, imports, error handling, comments, variable grouping
- **Spec compliance** — contradictions and missing required behavior
- **Code quality** — dead code, unused imports, leftover artifacts, unrelated changes
- **Graduated severity** — `approve_with_warnings` for minor issues, `request_changes` for substantive violations

All existing tests pass. Single file changed, no new placeholders introduced.
```

### Agent Stdout Tail
```text
mports, error handling, comments, variable grouping\n- **Spec compliance** — contradictions and missing required behavior\n- **Code quality** — dead code, unused imports, leftover artifacts, unrelated changes\n- **Graduated severity** — `approve_with_warnings` for minor issues, `request_changes` for substantive violations\n\nAll existing tests pass. Single file changed, no new placeholders introduced.","stop_reason":"end_turn","session_id":"6b1a70ab-41eb-452b-b551-4dac80a5e577","total_cost_usd":0.30944225,"usage":{"input_tokens":16,"cache_creation_input_tokens":20531,"cache_read_input_tokens":202937,"output_tokens":3183,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":20531},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":16,"outputTokens":3183,"cacheReadInputTokens":202937,"cacheCreationInputTokens":20531,"webSearchRequests":0,"costUSD":0.30944225,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"4f4ba896-5f98-42eb-a961-082055a066dc"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 29s

**Review Reasoning:** The diff correctly implements all ticket requirements:

- **Convention enforcement**: Covers naming, imports, error handling, comment style, variable grouping — all matching AGENTS.md rules.
- **Spec compliance**: Flags contradictions and missing required behavior.
- **Code quality**: Flags dead code, unused imports, leftover artifacts, unrelated changes with appropriate judgment caveat.
- **Graduated severity**: Minor → `approve_with_warnings`, substantive → `request_changes`, clean → `approve`.
- **CRITICAL instruction** preserved (moved to top, which is sensible — verify before reviewing).
- **`submit_review` exactly once** instruction preserved at the bottom.
- No new placeholders introduced; prompt-only change to a single file.
Approved. The prompt update is complete, accurate, and faithful to the ticket requirements and spec §9.

## Merge Queue Success
- Summary: Replaced the minimal Instructions section in review_agent.md with detailed enforcement instructions covering convention enforcement (AGENTS.md rules), spec compliance, code quality checks (dead code, unused imports, leftover artifacts), and graduated severity (approve_with_warnings for minor style issues, request_changes for substantive violations). No placeholders changed; existing tests pass.\n
### Quality Check Output
```text
45Z] [INFO] ticket 0001: post-analysis skipped (no prediction section)
[tests/integration_orchestrator_queue.nim] [2026-03-23T06:56:45Z] [INFO] journal: began transition — complete 0001
[tests/integration_orchestrator_queue.nim] [2026-03-23T06:56:45Z] [INFO] journal: executed steps — complete 0001
[tests/integration_orchestrator_queue.nim] [2026-03-23T06:56:45Z] [INFO] journal: transition complete
[tests/integration_orchestrator_queue.nim] [2026-03-23T06:56:45Z] [INFO] merge queue: item processed
[tests/integration_orchestrator_queue.nim] [2026-03-23T06:56:45Z] [INFO] tick 0 summary: architect=updated manager=no-op coding=1/4 agents merge=processing open=0 in-progress=0 done=1
[tests/integration_orchestrator_queue.nim] [2026-03-23T06:56:46Z] [INFO] shutdown: waiting for 1 running agent(s)
[tests/integration_orchestrator_queue.nim] [2026-03-23T06:57:18Z] [INFO] session summary: uptime=1m36s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[tests/integration_orchestrator_queue.nim] [2026-03-23T06:57:18Z] [INFO] session summary: avg_ticket_wall=32s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
[tests/integration_orchestrator_queue.nim]   [OK] IT-10 global halt while red resumes after master health is restored
[tests/integration_orchestrator_queue.nim] [2026-03-23T06:57:18Z] [INFO] recovery: clean startup, no recovery needed
[tests/integration_orchestrator_queue.nim] [2026-03-23T06:57:18Z] [WARN] master is unhealthy — skipping tick
[tests/integration_orchestrator_queue.nim] [2026-03-23T06:57:48Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[tests/integration_orchestrator_queue.nim] [2026-03-23T06:57:48Z] [INFO] session summary: avg_ticket_wall=32s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
[tests/integration_orchestrator_queue.nim]   [OK] IT-11 integration-test failure on master blocks assignment of open tickets
```

## Metrics
- wall_time_seconds: 491
- coding_wall_seconds: 83
- test_wall_seconds: 372
- attempt_count: 1
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 73723

## Post-Analysis
- actual_difficulty: easy
- prediction_accuracy: underestimated
- brief_summary: Predicted trivial, actual was easy with 1 attempt(s) in 8m11s.
