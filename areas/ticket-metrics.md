# Per-Ticket Metrics

V3 feature: structured per-ticket metrics persisted in agent run notes on the plan branch.

## Scope

- Required metrics fields per ticket:
  - `wall_time_seconds`: total elapsed time from assignment to done/reopen.
  - `coding_wall_seconds`: time spent in the coding agent (per attempt and total).
  - `test_wall_seconds`: time spent running make test (merge queue + stall checks).
  - `attempt_count`: number of coding agent attempts.
  - `outcome`: `done`, `reopened`, or `parked`.
  - `failure_reason`: `stall`, `test_failure`, `merge_conflict`, `timeout_hard`, `timeout_no_output`, or `parked` (only set when outcome is not `done`).
  - `model`: which model was used for the coding agent.
  - `stdout_bytes`: size of agent stdout in bytes (proxy for token usage).
- Metrics appended to the ticket markdown alongside existing agent run notes.
- Every completed or reopened ticket must have structured metrics with all listed fields present.
- Timing values are in seconds for machine readability.

## V3 Known Limitations

- `stdout_bytes` is a rough proxy for token usage; real token counts require harness-level API integration.

## Spec References

- Section 15: Per-Ticket Metrics In Agent Run Notes (V3).
