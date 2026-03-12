# Per-Ticket Metrics Persistence In Markdown

**Area:** ticket-metrics

## Description

Compute structured per-ticket metrics and append them to ticket markdown alongside existing agent run notes when a ticket reaches a terminal state (done, reopened, or parked).

## Current State

- `formatAgentRunNote()` appends model, backend, exit code, attempt info, timeout kind, log file, and stdout tail to ticket markdown.
- No structured metrics section exists in agent run notes.
- No outcome or failure reason classification.
- `stdout_bytes` is not computed.

## Requirements

- When a ticket reaches done, reopened, or parked state, append a structured metrics section to the ticket markdown.
- Required metrics fields:
  - `wall_time_seconds`: total elapsed time from assignment to done/reopen (integer seconds).
  - `coding_wall_seconds`: total time spent in coding agent across all attempts (integer seconds).
  - `test_wall_seconds`: total time spent running `make test` (merge queue + stall checks) (integer seconds).
  - `attempt_count`: number of coding agent attempts.
  - `outcome`: `done`, `reopened`, or `parked`.
  - `failure_reason`: `stall`, `test_failure`, `merge_conflict`, `timeout_hard`, `timeout_no_output`, or `parked` (only set when outcome is not `done`).
  - `model`: which model was used for the coding agent.
  - `stdout_bytes`: size of agent stdout in bytes.

- Every completed or reopened ticket must have all listed fields present.
- Metrics appended as a clearly delimited section (e.g., `## Metrics`) in the ticket markdown.

## Implementation Notes

- Read timing data from the `TicketTimings` infrastructure (ticket 0036).
- Classify outcome based on which terminal state the ticket entered.
- Determine failure_reason from the exit path (stall detection, test failure, merge conflict, timeout).
- Compute `stdout_bytes` from the agent stdout capture (already available in agent run results).
- Format as a markdown section and append via `appendAgentRunNote()` or a new dedicated proc.
- Commit the updated markdown to the plan branch.

## Spec References

- Section 15: Per-Ticket Metrics In Agent Run Notes (V3).
