# Ticket Post-Analysis After Completion

**Area:** ticket-prediction

## Description

After a ticket reaches done, reopened, or parked state, run a brief post-analysis comparing predicted vs actual metrics. Append the analysis to the ticket markdown and log it.

## Current State

No post-analysis infrastructure exists. Tickets move to terminal states without any retrospective analysis. Per-ticket metrics (from ticket 0037) and prediction data (from ticket 0038) will provide the inputs for comparison.

## Requirements

- After a ticket reaches done or is reopened/parked, run a post-analysis.
- Compare predicted vs actual metrics:
  - Predicted difficulty vs actual attempt count and outcome.
  - Predicted duration vs actual wall time.
- Post-analysis output fields:
  - `actual_difficulty`: assessment based on actual metrics (`trivial`, `easy`, `medium`, `hard`, `complex`).
  - `prediction_accuracy`: `accurate`, `underestimated`, or `overestimated`.
  - `brief_summary`: one-sentence summary of what happened.
- Log at INFO level: `ticket <id>: post-analysis: predicted=<level> actual=<level> accuracy=<accuracy> wall=<duration>`.
- Append as a `## Post-Analysis` section in the ticket markdown.

## Implementation Notes

- Read the prediction section from the ticket markdown to get predicted values.
- Read actual metrics from the metrics section (ticket 0037) or from orchestrator state.
- Classify actual difficulty based on attempt count, outcome, and wall time:
  - e.g., 1 attempt + done + short wall = trivial/easy; multiple attempts + reopened = hard/complex.
- Determine prediction accuracy by comparing predicted vs actual difficulty and duration.
- Generate brief_summary describing what happened (can be a simple template, no LLM call needed).
- If no prediction section exists (prediction was skipped), log and skip post-analysis.
- Append the post-analysis section and commit to plan branch.

## Spec References

- Section 19: Ticket Post-Analysis (V3).
