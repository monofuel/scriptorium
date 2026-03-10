# Stall Detection And Automatic Continuation

**Area:** stall-detection

## Problem

The orchestrator detects when a coding agent exits without calling `submit_pr` (`consumeSubmitPrSummary()` returns empty), but currently takes no action — it only logs at debug level and returns. The spec requires the orchestrator to retry the agent with a stall continuation prompt using the existing bounded retry mechanism.

The harnesses already support bounded retry and continuation prompts for timeout-based stalls, but the orchestrator does not invoke this mechanism when the agent exits cleanly without calling `submit_pr`.

## Requirements

- Define stall as: coding agent turn completes (process exits) without having called the `submit_pr` MCP tool.
- When a stall is detected in `executeAssignedTicket`, the orchestrator must retry the agent with a continuation prompt that includes:
  - The full original ticket content.
  - A reminder to continue working and call `submit_pr` when done.
- Stall-driven retries must use the existing `maxAttempts` mechanism in `AgentRunRequest` (do not invent new retry infrastructure).
- The continuation prompt must be distinct from the initial prompt — it must indicate this is a retry after a stall.
- Each stall retry must be logged with the attempt number and ticket ID.
- Retries stop after `maxAttempts` is reached.

## Acceptance Criteria

- When a coding agent exits without calling `submit_pr`, the orchestrator retries with the stall continuation prompt.
- Retries stop after `maxAttempts` is reached.
- Each retry is logged with attempt number and ticket ID.
- The continuation prompt includes the original ticket content.
- Unit tests in `test_agent_runner.nim` or `test_scriptorium.nim` cover the stall-retry path with a fake/mock runner.
