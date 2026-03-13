# Resource Management — Rate Limit Detection And Backpressure

**Area:** parallel-execution

## Problem

The V5 spec (§26) requires detecting HTTP 429 (rate limit) responses from agent harnesses and applying backpressure: exponential backoff before starting new agents and temporarily reducing effective concurrency.

## Requirements

1. Detect rate limit responses from agent harness execution:
   - Check agent process exit/output for HTTP 429 or equivalent rate limit indicators.
   - This depends on harness-specific error reporting (known limitation).
2. On rate limit detection:
   - Log: `resource limit: rate limited (ticket <id>, backing off <n>s)`.
   - Apply exponential backoff before starting new agents (not before retrying the failed agent).
   - Reduce effective concurrency by 1 temporarily until backoff period expires.
3. Backpressure mechanism:
   - Delay new agent starts when approaching rate limits rather than failing running agents.
   - Allow running agents to complete normally.
4. After backoff period expires, restore effective concurrency.
5. Add unit tests for:
   - Backoff timing increases exponentially.
   - Effective concurrency reduction on rate limit.
   - Concurrency restored after backoff expires.

## Dependencies

- Ticket 0049 (non-blocking tick — provides agent pool)
- Ticket 0050 (concurrent agent execution)

## Acceptance Criteria

- `make test` passes with new tests.
- Rate limit detection logged clearly.
- Running agents not interrupted by backpressure.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0052-resource-management-rate-limit-backpressure

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 35
- reasoning: Requires implementing exponential backoff logic, concurrency reduction/restoration, and rate limit detection in the agent pool, plus unit tests — moderately complex but well-scoped with clear acceptance criteria and existing infrastructure from dependency tickets.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0052-resource-management-rate-limit-backpressure/.scriptorium/logs/0052/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0052-resource-management-rate-limit-backpressure/.scriptorium/logs/0052/attempt-01.last_message.txt\n
### Agent Last Message
```text
All done. Here's a summary of what was implemented:

**Changes in `src/scriptorium/orchestrator.nim`:**
- Added `math` import for `pow`
- Added constants: `RateLimitBaseBackoffSeconds` (2s), `RateLimitMaxBackoffSeconds` (120s), `RateLimitBackoffMultiplier` (2x)
- Added state variables: `rateLimitBackoffUntil`, `rateLimitConsecutiveCount`, `rateLimitConcurrencyReduction`
- `isRateLimited(output)` — detects HTTP 429 and rate limit patterns in agent output
- `rateLimitBackoffSeconds()` — calculates exponential backoff duration
- `recordRateLimit(ticketId)` — logs and records rate limit event with the required log format
- `isRateLimitBackoffActive()` — checks/restores backoff state when expired
- `effectiveMaxAgents(maxAgents)` — reduces concurrency during backoff (min 1)
- `resetRateLimitState()` — clears all backpressure state
- Integrated into main loop: completed agents checked for rate limits, backoff blocks new agent starts, effective concurrency reduced in parallel mode

**Changes in `tests/test_scriptorium.nim`:**
- New test suite "rate limit detection and backpressure" with 8 tests covering all acceptance criteria
```

### Agent Stdout Tail
```text
urrency reduced in parallel mode\n\n**Changes in `tests/test_scriptorium.nim`:**\n- New test suite \"rate limit detection and backpressure\" with 8 tests covering all acceptance criteria","stop_reason":"end_turn","session_id":"6715c1a1-3baf-47c2-87d4-27f176dcf2f4","total_cost_usd":1.7169415,"usage":{"input_tokens":49,"cache_creation_input_tokens":47161,"cache_read_input_tokens":1867203,"output_tokens":11120,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":47161,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":49,"outputTokens":11120,"cacheReadInputTokens":1867203,"cacheCreationInputTokens":47161,"webSearchRequests":0,"costUSD":1.5066027499999997,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":21,"outputTokens":5999,"cacheReadInputTokens":942290,"cacheCreationInputTokens":68875,"webSearchRequests":0,"costUSD":0.21033875000000002,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"eb90d0db-2d35-47a9-b511-8756d80f06e9"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 137
- Wall Time: 5m0s

## Merge Queue Success
- Summary: Add rate limit detection and backpressure for agent pool. Detects HTTP 429/rate limit indicators in agent output, applies exponential backoff before starting new agents, reduces effective concurrency temporarily, and restores it after backoff expires. Running agents are never interrupted. Includes unit tests for backoff timing, concurrency reduction, and restoration.\n
### Quality Check Output
```text
ping tick
[2026-03-13T06:41:50Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=2 tickets_reopened=3 tickets_parked=0 merge_queue_processed=2
[2026-03-13T06:41:50Z] [INFO] session summary: avg_ticket_wall=0s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
[2026-03-13T06:41:50Z] [INFO] architect: generating areas from spec
[2026-03-13T06:41:51Z] [INFO] architect: areas updated
[2026-03-13T06:41:51Z] [INFO] manager: generating tickets
[2026-03-13T06:41:51Z] [INFO] merge queue: processing
[2026-03-13T06:41:51Z] [INFO] ticket 0001: review started (model=codex-fake-unit-test-model)
[2026-03-13T06:41:52Z] [WARN] ticket 0001: review agent stalled, defaulting to approve
[2026-03-13T06:41:52Z] [INFO] ticket 0001: merge started (make test running)
[2026-03-13T06:41:52Z] [INFO] ticket 0001: merge succeeded (test wall=0s)
[2026-03-13T06:41:52Z] [INFO] ticket 0001: in-progress -> done (total wall=31s, attempts=0)
[2026-03-13T06:41:52Z] [INFO] ticket 0001: post-analysis skipped (no prediction section)
[2026-03-13T06:41:52Z] [INFO] merge queue: item processed
[2026-03-13T06:41:52Z] [INFO] tick 0 summary: architect=updated manager=no-op coding=idle merge=processing open=0 in-progress=0 done=1
[2026-03-13T06:41:52Z] [INFO] session summary: uptime=1s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-13T06:41:52Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-10 global halt while red resumes after master health is restored
[2026-03-13T06:41:52Z] [WARN] master is unhealthy — skipping tick
[2026-03-13T06:42:22Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-13T06:42:22Z] [INFO] session summary: avg_ticket_wall=10s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-11 integration-test failure on master blocks assignment of open tickets
```

## Metrics
- wall_time_seconds: 1034
- coding_wall_seconds: 474
- test_wall_seconds: 249
- attempt_count: 1
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 1781705

## Post-Analysis
- actual_difficulty: medium
- prediction_accuracy: accurate
- brief_summary: Predicted medium, actual was medium with 1 attempt(s) in 17m14s.
