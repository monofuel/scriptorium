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

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0037-per-ticket-metrics-persistence

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0037-per-ticket-metrics-persistence/.scriptorium/logs/0037/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0037-per-ticket-metrics-persistence/.scriptorium/logs/0037/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Here's a summary of what was implemented:

**Changes to `src/scriptorium/orchestrator.nim`:**
- Added `ticketModels` and `ticketStdoutBytes` tracking tables alongside existing timing tables
- Initialized new tables at ticket assignment time
- Populated model and stdout_bytes after each coding agent run
- Added `formatMetricsNote` - formats a `## Metrics` section with all 8 required fields
- Added `appendMetricsNote` - appends metrics section to ticket markdown
- Added `cleanupTicketTimings` - centralizes cleanup of all 6 per-ticket state tables
- Appends metrics at all 5 terminal state paths: done, parked, reopened (merge conflict/test failure, worktree missing, no submit_pr)
- Classifies `failure_reason` from exit path: `stall`, `test_failure`, `merge_conflict`, `timeout_hard`, `timeout_no_output`, or `parked`

**Changes to `tests/test_scriptorium.nim`:**
- Added "per-ticket metrics" test suite with 6 tests covering formatting, appending, cleanup, and defaults
```

### Agent Stdout Tail
```text
ut_hard`, `timeout_no_output`, or `parked`\n\n**Changes to `tests/test_scriptorium.nim`:**\n- Added \"per-ticket metrics\" test suite with 6 tests covering formatting, appending, cleanup, and defaults","stop_reason":"end_turn","session_id":"334cb4cb-8083-4836-9428-509e913ce80c","total_cost_usd":2.0287514,"usage":{"input_tokens":50,"cache_creation_input_tokens":51727,"cache_read_input_tokens":2163775,"output_tokens":14969,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":51727,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":50,"outputTokens":14969,"cacheReadInputTokens":2163775,"cacheCreationInputTokens":51727,"webSearchRequests":0,"costUSD":1.77965625,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":1360,"outputTokens":9612,"cacheReadInputTokens":1317489,"cacheCreationInputTokens":54341,"webSearchRequests":0,"costUSD":0.24909515,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"fcbc68a5-c6b4-4e78-9651-158b0e3febd6"}
```
