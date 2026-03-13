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
