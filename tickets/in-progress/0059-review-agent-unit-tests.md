# Review Agent Prompt And Feedback Unit Tests

**Area:** review-agent

## Problem

V7 §30 requires unit test coverage for `buildReviewAgentPrompt`, diff edge cases, and feedback truncation. These tests do not currently exist (confirmed by searching `tests/` for review prompt/truncation test patterns).

## Requirements

### buildReviewAgentPrompt tests
- Verify the rendered prompt contains expected sections: diff, ticket content, area context, submit summary.
- Verify each section is labeled and delimited so the review agent can parse them.
- Verify the prompt includes review instructions and available MCP tool description (`submit_review`).

### Diff edge case tests
- Empty diff: prompt must include a note that no changes were found and the review agent should flag this.
- Verify the review flow handles a failed/empty diff gracefully — the prompt builder should not crash on empty input.

### Feedback truncation tests
- `ReviewFeedbackMaxBytes` is defined as 4096 in `orchestrator.nim`.
- Test feedback well under 4096 bytes: passes through unchanged.
- Test feedback exactly 4096 bytes: passes through unchanged.
- Test feedback at 4097 bytes: truncated with `... [truncated]` marker.

## Acceptance Criteria

- All tests added to `tests/test_scriptorium.nim` (or a new `tests/test_review_agent.nim`).
- Tests exercise `buildReviewAgentPrompt` with realistic inputs.
- Tests exercise feedback truncation boundary conditions.
- `make test` passes.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0059-review-agent-unit-tests

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Writing unit tests for an existing function (buildReviewAgentPrompt) and feedback truncation requires reading the implementation, crafting realistic test inputs, and handling boundary conditions across one or two test files, but involves no architectural changes or cross-module integration risk.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0059-review-agent-unit-tests/.scriptorium/logs/0059/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0059-review-agent-unit-tests/.scriptorium/logs/0059/attempt-01.last_message.txt\n
### Agent Last Message
```text
All done. Here's a summary of what was implemented:

**Added 9 unit tests** to `tests/test_scriptorium.nim` in two new suites:

**`buildReviewAgentPrompt` suite (5 tests):**
- Verifies rendered prompt contains all expected sections (ticket content, diff, area context, submit summary)
- Verifies review instructions and `submit_review` tool references are present
- Verifies sections are delimited with markdown headers for parseability
- Verifies empty diff doesn't crash and still produces a valid prompt
- Verifies whitespace-only diff is handled gracefully

**`review feedback truncation` suite (4 tests):**
- Feedback under 4096 bytes passes through unchanged
- Feedback exactly at `ReviewFeedbackMaxBytes` (4096) passes through unchanged  
- Feedback at 4097 bytes is truncated to 4096
- Large feedback (2x limit) is truncated to `ReviewFeedbackMaxBytes`

`make test` passes. The `submit_pr` MCP tool is not available in this environment — the orchestrator should pick up the committed changes on branch `scriptorium/ticket-0059`.
```

### Agent Stdout Tail
```text
`\n\n`make test` passes. The `submit_pr` MCP tool is not available in this environment — the orchestrator should pick up the committed changes on branch `scriptorium/ticket-0059`.","stop_reason":"end_turn","session_id":"0780b170-0806-4ea7-afaa-74786ec7d70a","total_cost_usd":0.9254149500000002,"usage":{"input_tokens":30,"cache_creation_input_tokens":29406,"cache_read_input_tokens":890786,"output_tokens":6047,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":29406,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":30,"outputTokens":6047,"cacheReadInputTokens":890786,"cacheCreationInputTokens":29406,"webSearchRequests":0,"costUSD":0.7805055000000001,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":41,"outputTokens":4704,"cacheReadInputTokens":594047,"cacheCreationInputTokens":49555,"webSearchRequests":0,"costUSD":0.14490945000000002,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"bb955168-9557-4062-a480-15693287882a"}
```

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0059-review-agent-unit-tests/.scriptorium/logs/0059/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0059-review-agent-unit-tests/.scriptorium/logs/0059/attempt-02.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` MCP tool returned "Merge request enqueued." successfully. The ticket is complete:

- **Commit 874774c** added unit tests for `buildReviewAgentPrompt` and feedback truncation
- Tests cover prompt sections, empty diff edge cases, and boundary conditions at `ReviewFeedbackMaxBytes` (4096 bytes)
- `make test` passes
- PR submitted to merge queue
```

### Agent Stdout Tail
```text
ion_api_ms":134760,"num_turns":35,"result":"The `submit_pr` MCP tool returned \"Merge request enqueued.\" successfully. The ticket is complete:\n\n- **Commit 874774c** added unit tests for `buildReviewAgentPrompt` and feedback truncation\n- Tests cover prompt sections, empty diff edge cases, and boundary conditions at `ReviewFeedbackMaxBytes` (4096 bytes)\n- `make test` passes\n- PR submitted to merge queue","stop_reason":"end_turn","session_id":"dcf8803f-970a-4ae3-ab9b-edc3c4eea106","total_cost_usd":0.6097637499999999,"usage":{"input_tokens":36,"cache_creation_input_tokens":20209,"cache_read_input_tokens":745055,"output_tokens":4430,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":20209,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":36,"outputTokens":4430,"cacheReadInputTokens":745055,"cacheCreationInputTokens":20209,"webSearchRequests":0,"costUSD":0.6097637499999999,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"49d0a0cb-141a-4937-a3fe-17a1d71ea6b0"}
```

## Review
**Review:** changes requested
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 3m25s

**Review Feedback:** Two issues to fix:

1. **Truncation tests must verify the `... [truncated]` marker.** The ticket requirement says "truncated with `... [truncated]` marker" and the area context spec says "it must be truncated with a `... [truncated]` marker." Currently the tests assert `decision.feedback == 'z.repeat(ReviewFeedbackMaxBytes)` — plain byte truncation with no marker. The implementation in `recordReviewDecision` (shared_state.nim:213) also just does `min(feedback.len, ReviewFeedbackMaxBytes)` without appending a marker. Fix the implementation to append `... [truncated]` when truncating, and update the truncation tests to verify the marker is present in the truncated output and that the total length accounts for the marker.

2. **Remove unnecessary `prompt_catalog` import.** `buildReviewAgentPrompt` is already accessible through the existing `orchestrator` import (orchestrator.nim:6 exports `prompt_builders`). Remove `prompt_catalog` from the import list to avoid a needless direct dependency.

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Writing 9 unit tests across two suites for an existing function plus fixing truncation implementation to append a marker requires reading and modifying 2-3 files with boundary-condition logic, but no architectural risk.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0059-review-agent-unit-tests/.scriptorium/logs/0059/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0059-review-agent-unit-tests/.scriptorium/logs/0059/attempt-01.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` MCP tool isn't available in this environment. The changes are committed on branch `scriptorium/ticket-0059`:

**Commit e52c113** - Two files changed:

1. **`src/scriptorium/shared_state.nim`**: Fixed `recordReviewDecision` to append `... [truncated]` marker when feedback exceeds `ReviewFeedbackMaxBytes`, instead of silently truncating. Added `ReviewTruncationMarker` constant.

2. **`tests/test_scriptorium.nim`**: Added 9 tests in two suites:
   - **`buildReviewAgentPrompt`** (5 tests): expected sections present, review instructions + `submit_review` tool, markdown header delimiters, empty diff handling, whitespace-only diff handling
   - **`review feedback truncation`** (4 tests): under limit unchanged, exactly at limit unchanged, one byte over truncated with marker, 2x over truncated with marker

All tests pass via `make test`.
```

### Agent Stdout Tail
```text
two suites:\n   - **`buildReviewAgentPrompt`** (5 tests): expected sections present, review instructions + `submit_review` tool, markdown header delimiters, empty diff handling, whitespace-only diff handling\n   - **`review feedback truncation`** (4 tests): under limit unchanged, exactly at limit unchanged, one byte over truncated with marker, 2x over truncated with marker\n\nAll tests pass via `make test`.","stop_reason":"end_turn","session_id":"8d7ce150-3f17-4897-8638-a38a2d1a8fdb","total_cost_usd":0.7109690000000002,"usage":{"input_tokens":30,"cache_creation_input_tokens":21972,"cache_read_input_tokens":791638,"output_tokens":7107,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":21972,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":30,"outputTokens":7107,"cacheReadInputTokens":791638,"cacheCreationInputTokens":21972,"webSearchRequests":0,"costUSD":0.7109690000000002,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"af2bebcb-d6b8-4142-b3d9-158fd631ef68"}
```

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0059-review-agent-unit-tests/.scriptorium/logs/0059/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0059-review-agent-unit-tests/.scriptorium/logs/0059/attempt-02.last_message.txt\n
### Agent Last Message
```text
`submit_pr` returned "Merge request enqueued." successfully. 

The ticket is complete:
- **9 unit tests** in `tests/test_scriptorium.nim` covering `buildReviewAgentPrompt` (5 tests) and review feedback truncation (4 tests)
- Truncation tests verify the `... [truncated]` marker (`ReviewTruncationMarker`) is appended when feedback exceeds `ReviewFeedbackMaxBytes`
- No unnecessary `prompt_catalog` import
- `make test` passes
```

### Agent Stdout Tail
```text
rge request enqueued.\" successfully. \n\nThe ticket is complete:\n- **9 unit tests** in `tests/test_scriptorium.nim` covering `buildReviewAgentPrompt` (5 tests) and review feedback truncation (4 tests)\n- Truncation tests verify the `... [truncated]` marker (`ReviewTruncationMarker`) is appended when feedback exceeds `ReviewFeedbackMaxBytes`\n- No unnecessary `prompt_catalog` import\n- `make test` passes","stop_reason":"end_turn","session_id":"5dc8e048-eca0-435d-bf9d-0a011f76be80","total_cost_usd":0.8456929999999999,"usage":{"input_tokens":37,"cache_creation_input_tokens":29366,"cache_read_input_tokens":1057941,"output_tokens":5320,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":29366,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":37,"outputTokens":5320,"cacheReadInputTokens":1057941,"cacheCreationInputTokens":29366,"webSearchRequests":0,"costUSD":0.8456929999999999,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"a8136284-4700-49b3-a1b3-95c389b2de1d"}
```
