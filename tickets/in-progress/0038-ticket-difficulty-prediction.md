# Ticket Difficulty Prediction Before Assignment

**Area:** ticket-prediction

## Description

Before a ticket is assigned to a coding agent, run a lightweight prediction prompt to estimate ticket difficulty and expected duration. Append the prediction to the ticket markdown and log it.

## Current State

No prediction infrastructure exists. Tickets are assigned directly to coding agents without any pre-analysis. The codex harness is available for running agent calls, and `TicketDocument` holds ticket content.

## Requirements

- Before ticket assignment, invoke a prediction prompt via the configured coding agent model (codex harness).
- Prediction prompt context includes: ticket content, relevant area content, current spec summary.
- Prediction output fields:
  - `predicted_difficulty`: `trivial`, `easy`, `medium`, `hard`, or `complex`.
  - `predicted_duration_minutes`: estimated wall time in minutes.
  - `reasoning`: brief explanation of the prediction.
- Log at INFO level: `ticket <id>: predicted difficulty=<level> duration=<n>min`.
- Append prediction as a `## Prediction` section in the ticket markdown before coding begins.
- Prediction must not significantly delay ticket assignment (use a short timeout or fast model invocation).

## Implementation Notes

- Create a prediction prompt template that asks the model to assess difficulty given the ticket and area content.
- Parse structured output (JSON or key-value) from the model response.
- Call the codex harness with a short timeout for the prediction.
- If prediction fails or times out, log a warning and proceed with assignment (prediction is best-effort).
- Append the prediction section to ticket markdown and commit to plan branch before starting the coding agent.

## Spec References

- Section 18: Ticket Difficulty Prediction (V3).

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0038-ticket-difficulty-prediction
