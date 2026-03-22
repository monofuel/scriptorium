# Concurrency Model Documentation

**Area:** parallel-execution

**Depends:** 0071

## Problem

V13 §33 requires documenting the concurrency model to clarify which agents are sequential vs parallel, how the shared slot pool works, and how merge conflicts are handled.

## Requirements

Add a `## Concurrency Model` section to the project's `AGENTS.md` (or a dedicated doc file if more appropriate) covering:

1. **Strictly sequential agents**: Architect (reads spec, writes areas, runs at most once per tick, protected by plan lock, must complete before managers) and Review/Merge (one merge queue item at a time, sequential to guarantee default branch health).
2. **Parallel agents (shared slot pool)**: Manager (one area per invocation, multiple can run in parallel) and Coding agent (one ticket per invocation, multiple can run in parallel in independent areas). Both share the `maxAgents` slot pool.
3. **Interleaved execution**: Managers and coders interleaved across ticks — orchestrator does not wait for all managers to finish before starting coders.
4. **Merge conflict handling**: Parallel coding agents may produce merge conflicts on shared files. Sequential merge process catches conflicts by merging default branch into ticket branch before testing. Conflicting tickets sent back for another coding attempt with conflict context. Area-based separation makes conflicts less likely but system handles them gracefully.
5. **Slot arithmetic**: Example — if `maxAgents` is 4 and 2 managers are running, only 2 slots remain for coders (and vice versa).

Keep the documentation concise. `make test` must still pass.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0073-concurrency-model-documentation

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 10
- reasoning: Documentation-only ticket adding a concurrency model section to AGENTS.md with no code logic changes, just clear prose matching the detailed requirements already specified in the ticket.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0073-concurrency-model-documentation/.scriptorium/logs/0073/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0073-concurrency-model-documentation/.scriptorium/logs/0073/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Added a `## Concurrency Model` section to `AGENTS.md` (between "Agent completion protocol" and "Nim") covering all five required topics: sequential agents, parallel agents with shared slot pool, interleaved execution, slot arithmetic, and merge conflict handling.
```

### Agent Stdout Tail
```text
9c00f3bfa4e"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":150682,"duration_api_ms":44892,"num_turns":9,"result":"Done. Added a `## Concurrency Model` section to `AGENTS.md` (between \"Agent completion protocol\" and \"Nim\") covering all five required topics: sequential agents, parallel agents with shared slot pool, interleaved execution, slot arithmetic, and merge conflict handling.","stop_reason":"end_turn","session_id":"9abcc29f-4515-4b2f-8687-73904d33d2c1","total_cost_usd":0.20338575,"usage":{"input_tokens":12,"cache_creation_input_tokens":16655,"cache_read_input_tokens":108064,"output_tokens":1808,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":16655},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":12,"outputTokens":1808,"cacheReadInputTokens":108064,"cacheCreationInputTokens":16655,"webSearchRequests":0,"costUSD":0.20338575,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"7cf51ac0-ed61-447d-b2f7-c62534b303f2"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 13s

## Merge Queue Success
- Summary: Added a Concurrency Model section to AGENTS.md covering: strictly sequential agents (Architect, Review/Merge), parallel agents sharing the maxAgents slot pool (Manager, Coding agent), interleaved execution across ticks, slot arithmetic, and merge conflict handling.\n
### Quality Check Output
```text
Z] [INFO] ticket 0001: merge succeeded (test wall=0s)
[2026-03-22T08:03:08Z] [INFO] ticket 0001: in-progress -> done (total wall=1m34s, attempts=0)
[2026-03-22T08:03:08Z] [INFO] ticket 0001: post-analysis skipped (no prediction section)
[2026-03-22T08:03:08Z] [INFO] journal: began transition — complete 0001
[2026-03-22T08:03:08Z] [INFO] journal: executed steps — complete 0001
[2026-03-22T08:03:08Z] [INFO] journal: transition complete
[2026-03-22T08:03:08Z] [INFO] merge queue: item processed
[2026-03-22T08:03:08Z] [INFO] tick 0 summary: architect=updated manager=no-op coding=1/4 agents merge=processing open=0 in-progress=0 done=1
[2026-03-22T08:03:08Z] [INFO] shutdown: waiting for 1 running agent(s)
[2026-03-22T08:03:22Z] [INFO] session summary: uptime=1m18s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-22T08:03:22Z] [INFO] session summary: avg_ticket_wall=31s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-10 global halt while red resumes after master health is restored
[2026-03-22T08:03:22Z] [INFO] recovery: clean startup, no recovery needed
[2026-03-22T08:03:22Z] [INFO] agent slots: 0/4 (manager queue-processing finished, 1 tickets)
[2026-03-22T08:03:22Z] [WARN] master is unhealthy — skipping tick
[2026-03-22T08:03:52Z] [INFO] session summary: uptime=30s ticks=1 tickets_completed=3 tickets_reopened=3 tickets_parked=0 merge_queue_processed=3
[2026-03-22T08:03:52Z] [INFO] session summary: avg_ticket_wall=31s avg_coding_wall=0s avg_test_wall=0s first_attempt_success=100%
  [OK] IT-11 integration-test failure on master blocks assignment of open tickets
--- tests/integration_review_agent_live.nim ---

[Suite] integration review agent live
  [OK] IT-REVIEW-01 real review agent calls submit_review with a real model
--- tests/integration_typoi_harness.nim ---

[Suite] integration typoi harness
  [SKIPPED] real typoi one-shot smoke test
  [SKIPPED] real typoi MCP tool call against live server
```

## Metrics
- wall_time_seconds: 565
- coding_wall_seconds: 152
- test_wall_seconds: 394
- attempt_count: 1
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 58109

## Post-Analysis
- actual_difficulty: easy
- prediction_accuracy: accurate
- brief_summary: Predicted easy, actual was easy with 1 attempt(s) in 9m25s.
