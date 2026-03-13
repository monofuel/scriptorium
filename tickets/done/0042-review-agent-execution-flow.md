# Review Agent Execution Flow In Merge Queue

**Area:** agent-execution

## Problem

After the `submit_review` MCP tool and reviewer config are in place (ticket 0041), the orchestrator needs to actually run a review agent session during merge queue processing, before the quality gates.

## Dependencies

- Ticket 0041 (review agent config and MCP tool) must be completed first.

## Requirements

### Review agent prompt

- Create a review agent prompt template (in `src/scriptorium/prompts/` or inline).
- Prompt includes:
  - Full ticket content (intent and requirements).
  - Diff of changes against `master` (via `git diff master...ticket-branch`).
  - Relevant area content (read from plan branch).
  - Submit summary from the coding agent.
- Instruct the review agent to call `submit_review` with `approve` or `request_changes`.

### Orchestrator integration (`orchestrator.nim`)

- In `processMergeQueue()`, after setting `active.md` but before merging master and running quality gates:
  1. Run a review agent session in the ticket's worktree using the reviewer config.
  2. After the review agent exits, consume the review decision.
  3. If approved (or stall — no `submit_review` called): proceed with existing merge flow.
  4. If changes requested:
     - Remove the pending merge queue item.
     - Append review feedback section to ticket markdown.
     - Start a new coding agent session with original ticket content plus review feedback.
     - The coding agent must call `submit_pr` again, triggering the full flow.
     - Review-driven retries count toward the ticket's total attempt count.

### Review notes in ticket markdown

- Append structured review notes: `**Review:** approved` or `**Review:** changes requested`.
- When changes requested: `**Review Feedback:** <feedback text>`.
- Include backend, exit code, and wall time consistent with agent run notes.

### Lifecycle logging

- `ticket <id>: review started (model=<model>)`
- `ticket <id>: review approved`
- `ticket <id>: review requested changes (feedback="<summary>")`
- `ticket <id>: review agent stalled, defaulting to approve`

## Acceptance Criteria

- Merge queue runs review agent before quality gates.
- Approved reviews proceed to merge.
- Stalled reviews default to approval with warning log.
- Change requests restart coding agent with feedback.
- Review notes appended to ticket markdown.
- Lifecycle log lines emitted for all review outcomes.
- Unit tests cover approve, request_changes, and stall paths.

## Spec References

- Section 21: Review Agent (V4).

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0042-review-agent-execution-flow

## Prediction
- predicted_difficulty: hard
- predicted_duration_minutes: 55
- reasoning: Requires orchestrator flow changes with multiple branching paths (approve/reject/stall), prompt template creation, ticket markdown mutation, retry logic restarting the coding agent, and unit tests covering all three review outcome paths.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0042-review-agent-execution-flow/.scriptorium/logs/0042/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0042-review-agent-execution-flow/.scriptorium/logs/0042/attempt-01.last_message.txt\n
### Agent Last Message
```text
Changes committed and merge request enqueued. Here's a summary of what was implemented:

**Files changed (5):**
- `src/scriptorium/prompts/review_agent.md` — New review agent prompt template with ticket content, diff, area context, and submit summary placeholders
- `src/scriptorium/prompt_catalog.nim` — Added `ReviewAgentTemplate` constant
- `src/scriptorium/orchestrator.nim` — Core implementation:
  - `buildReviewAgentPrompt` — renders the review prompt template
  - `runReviewAgent` — runs the review agent session, consumes the decision, writes review notes to ticket markdown
  - `processMergeQueue` — now accepts a `runner` param, runs review agent after auto-commit but before quality gates; on `request_changes`, reopens ticket with feedback
  - Review constants for timeouts and commit prefix
- `tests/test_scriptorium.nim` — Three new unit tests (approve, request_changes, stall) plus updated existing tests to pass `noopRunner`
- `tests/integration_orchestrator_queue.nim` — Updated to pass `noopRunner` for review agent
```

### Agent Stdout Tail
```text
prove, request_changes, stall) plus updated existing tests to pass `noopRunner`\n- `tests/integration_orchestrator_queue.nim` — Updated to pass `noopRunner` for review agent","stop_reason":"end_turn","session_id":"10b42b77-d140-4a9b-93db-1e283841a00a","total_cost_usd":4.055049099999999,"usage":{"input_tokens":80,"cache_creation_input_tokens":88217,"cache_read_input_tokens":5338584,"output_tokens":24622,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":88217,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":80,"outputTokens":24622,"cacheReadInputTokens":5338584,"cacheCreationInputTokens":88217,"webSearchRequests":0,"costUSD":3.8365982499999993,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":2347,"outputTokens":7439,"cacheReadInputTokens":1081451,"cacheCreationInputTokens":56611,"webSearchRequests":0,"costUSD":0.21845085000000003,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"f1f78acc-850e-4730-8848-a9e6c4afef19"}
```

## Merge Queue Success
- Summary: Add review agent execution flow in merge queue: review prompt template, runReviewAgent proc, processMergeQueue integration with approve/request_changes/stall handling, ticket markdown review notes, lifecycle logging, and unit tests for all three review paths.\n
### Quality Check Output
```text
ping tick
[2026-03-13T02:28:18Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=2 tickets_reopened=3 tickets_parked=0 merge_queue_processed=2
[2026-03-13T02:28:18Z] [INFO] session summary: avg_ticket_wall=0s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
[2026-03-13T02:28:18Z] [INFO] architect: generating areas from spec
[2026-03-13T02:28:20Z] [INFO] architect: areas updated
[2026-03-13T02:28:20Z] [INFO] manager: generating tickets
[2026-03-13T02:28:20Z] [INFO] merge queue: processing
[2026-03-13T02:28:20Z] [INFO] ticket 0001: review started (model=codex-fake-unit-test-model)
[2026-03-13T02:28:20Z] [WARN] ticket 0001: review agent stalled, defaulting to approve
[2026-03-13T02:28:20Z] [INFO] ticket 0001: merge started (make test running)
[2026-03-13T02:28:20Z] [INFO] ticket 0001: merge succeeded (test wall=0s)
[2026-03-13T02:28:20Z] [INFO] ticket 0001: in-progress -> done (total wall=31s, attempts=0)
[2026-03-13T02:28:20Z] [INFO] ticket 0001: post-analysis skipped (no prediction section)
[2026-03-13T02:28:20Z] [INFO] merge queue: item processed
[2026-03-13T02:28:20Z] [INFO] tick 0 summary: architect=updated manager=no-op coding=idle merge=processing open=0 in-progress=0 done=1
[2026-03-13T02:28:20Z] [INFO] session summary: uptime=2s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-13T02:28:20Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-10 global halt while red resumes after master health is restored
[2026-03-13T02:28:20Z] [WARN] master is unhealthy — skipping tick
[2026-03-13T02:28:50Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-13T02:28:50Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-11 integration-test failure on master blocks assignment of open tickets
```

## Metrics
- wall_time_seconds: 1649
- coding_wall_seconds: 1393
- test_wall_seconds: 245
- attempt_count: 1
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 2327851

## Post-Analysis
- actual_difficulty: medium
- prediction_accuracy: overestimated
- brief_summary: Predicted hard, actual was medium with 1 attempt(s) in 27m29s.
