# Migrate Ticket State Transitions To Journal

**Area:** crash-recovery
**Depends:** 0066

Migrate all ticket state transitions to use the write-ahead journal for crash safety (V8, §32).

## Requirements

All ticket state transitions must go through the journal protocol:

1. **open -> in-progress** (ticket assignment in `ticket_assignment.nim`):
   - Journal steps: `move` ticket file from `tickets/open/` to `tickets/in-progress/`, `write` updated content with worktree path.

2. **in-progress -> done** (merge success in `merge_queue.nim`):
   - Journal steps: `move` ticket file from `tickets/in-progress/` to `tickets/done/`, `write` updated content with metrics.

3. **in-progress -> open** (reopen on failure in `coding_agent.nim`):
   - Journal steps: `write` updated ticket content with run notes, `move` from `tickets/in-progress/` to `tickets/open/`.

## Implementation Notes

- Use `beginJournalTransition`, `executeJournalSteps`, `completeJournalTransition` from journal infrastructure (ticket 0066).
- Each transition is a single journal operation.
- Replace direct `moveFile` + `gitRun("add")` + `gitRun("commit")` sequences with journal-based equivalents.
- The journal adds two extra commits per transition (journal write and removal) — this is expected per V8 known limitations.

## Acceptance Criteria

- All three ticket state transitions use the journal protocol.
- Each transition creates and cleans up the journal file.
- Existing integration tests continue to pass.
- No `.scriptorium-journal.json` persists after clean operations.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0070-journal-ticket-state-transitions

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Three well-defined state transitions in three separate files need refactoring from direct file ops to journal API calls; the journal infrastructure already exists from ticket 0066, so this is mechanical multi-file plumbing with moderate integration risk.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0070-journal-ticket-state-transitions/.scriptorium/logs/0070/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0070-journal-ticket-state-transitions/.scriptorium/logs/0070/attempt-01.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` MCP tool was called successfully. The merge request has been enqueued.

**Summary of changes:**

1. **`ticket_assignment.nim`**: Migrated `assignOldestOpenTicket` and `assignOpenTickets` to use journal protocol for open → in-progress transitions. Steps: move ticket file, write updated content with worktree path.

2. **`coding_agent.nim`**: Migrated the reopen-on-failure path in `executeAssignedTicket` to use journal protocol for in-progress → open transitions. Steps: write updated content with metrics, move ticket back to open.

3. **`merge_queue.nim`**: Migrated all 5 transition sites to use journal protocol:
   - Success path (in-progress → done)
   - Missing worktree reopen (in-progress → open)
   - Review changes reopen (in-progress → open)
   - Stuck parking (in-progress → stuck)
   - Merge failure reopen (in-progress → open)

4. **`tests/test_scriptorium.nim`**: Updated commit count assertions to account for 2 extra journal commits per transition (begin + complete wrappers). Fixed orchestrator tick test to add a branch commit so startup recovery doesn't skip-complete the ticket.
```

### Agent Stdout Tail
```text
sertions to account for 2 extra journal commits per transition (begin + complete wrappers). Fixed orchestrator tick test to add a branch commit so startup recovery doesn't skip-complete the ticket.","stop_reason":"end_turn","session_id":"30a7a350-416d-465c-84df-a643d450d6df","total_cost_usd":5.455048999999999,"usage":{"input_tokens":75,"cache_creation_input_tokens":116964,"cache_read_input_tokens":7104152,"output_tokens":43446,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":116964,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":75,"outputTokens":43446,"cacheReadInputTokens":7104152,"cacheCreationInputTokens":116964,"webSearchRequests":0,"costUSD":5.369626,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":30,"outputTokens":3344,"cacheReadInputTokens":90455,"cacheCreationInputTokens":47702,"webSearchRequests":0,"costUSD":0.085423,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"89baa198-ccbb-4051-b683-9909e4db7281"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 2m37s
