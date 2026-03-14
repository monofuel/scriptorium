# Write-Ahead Journal Infrastructure

**Area:** crash-recovery

Implement the write-ahead journal file structure and protocol for atomic plan branch transitions (V8, §32).

## Requirements

### Journal File Structure
- Journal file: `.scriptorium-journal.json` in the plan worktree root.
- JSON structure with fields:
  - `operation`: string describing the transition (e.g., "ticket-assign", "merge-enqueue").
  - `timestamp`: ISO-8601 timestamp.
  - `steps`: array of step objects, each with `action` (`write`, `move`, `remove`) and relevant fields (`path`, `content`, `contentHash`, `source`, `destination`).
  - `commit_message`: the final commit message for the transition.

### Write-Ahead Protocol
1. Write the journal file describing all intended steps.
2. `git add` and commit the journal with `scriptorium: begin transition — <operation>`.
3. Execute filesystem operations (writes, moves, removes) as described in steps.
4. `git add -A` and commit with the transition's `commit_message`.
5. Remove the journal and commit with `scriptorium: complete transition`.

### Journal Replay/Rollback (for crash recovery)
- Read journal and inspect filesystem state for each step:
  - `write`: check file exists with expected content hash.
  - `move`: check destination exists, source does not.
  - `remove`: check file no longer exists.
- All steps applied: commit pending changes and remove journal (complete).
- Partial: replay remaining steps, commit, remove journal.
- None applied: roll back via `git checkout -- .`, remove journal, commit.
- Log: `recovery: rolled back incomplete transition` (or replayed/completed as appropriate).
- Replay/rollback must be deterministic — no human intervention required.

## Implementation Notes

- Create a new module `journal.nim` under `src/scriptorium/`.
- Export procs: `beginJournalTransition`, `executeJournalSteps`, `completeJournalTransition`, `replayOrRollbackJournal`, `journalExists`.
- Content hashes use SHA-1 (consistent with existing hash usage in the project).
- No journal file should persist across a clean orchestrator run.

## Acceptance Criteria

- Journal can be created, committed, executed, and cleaned up.
- Replay correctly handles: all-applied, partially-applied, and none-applied states.
- Rollback restores files to pre-transition state.
- Unit tests cover all three replay scenarios plus normal completion path.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0066-write-ahead-journal-infrastructure

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Single new module with well-specified interfaces and JSON/git operations, but the three-scenario replay/rollback state machine and corresponding unit tests add moderate logic complexity.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0066-write-ahead-journal-infrastructure/.scriptorium/logs/0066/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0066-write-ahead-journal-infrastructure/.scriptorium/logs/0066/attempt-01.last_message.txt\n
### Agent Last Message
```text
ubmit_pr` MCP tool is not available in this session's toolset - it's served by the scriptorium orchestrator MCP server which isn't connected here. 

Here's a summary of what was implemented:

**New file: `src/scriptorium/journal.nim`** — Write-ahead journal module with:
- `journalExists` — checks for journal file in worktree
- `beginJournalTransition` — writes journal JSON, commits it with begin message
- `executeJournalSteps` — executes write/move/remove steps from journal, commits with transition message
- `completeJournalTransition` — removes journal file, commits completion
- `replayOrRollbackJournal` — crash recovery: detects all-applied (complete), none-applied (rollback via `git checkout -- .`), or partial (replay remaining steps)
- Helper constructors: `newWriteStep`, `newMoveStep`, `newRemoveStep`

**New file: `tests/test_journal.nim`** — 6 tests covering:
- Journal existence check
- JSON serialization round-trip
- Normal begin → execute → complete flow
- Recovery: all steps applied → completes transition
- Recovery: no steps applied → rolls back
- Recovery: partial steps applied → replays remaining

All existing tests continue to pass (0 failures).
```

### Agent Stdout Tail
```text
all steps applied → completes transition\n- Recovery: no steps applied → rolls back\n- Recovery: partial steps applied → replays remaining\n\nAll existing tests continue to pass (0 failures).","stop_reason":"end_turn","session_id":"93c87679-4619-4d72-9073-ad320da674cf","total_cost_usd":1.11796095,"usage":{"input_tokens":36,"cache_creation_input_tokens":38897,"cache_read_input_tokens":1113123,"output_tokens":9307,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":38897,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":36,"outputTokens":9307,"cacheReadInputTokens":1113123,"cacheCreationInputTokens":38897,"webSearchRequests":0,"costUSD":1.0325227499999998,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":49,"outputTokens":4045,"cacheReadInputTokens":157217,"cacheCreationInputTokens":39554,"webSearchRequests":0,"costUSD":0.0854382,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"bcf2bd60-bb95-4de1-9ccd-cf39352268be"}
```

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0066-write-ahead-journal-infrastructure/.scriptorium/logs/0066/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0066-write-ahead-journal-infrastructure/.scriptorium/logs/0066/attempt-02.last_message.txt\n
### Agent Last Message
```text
`submit_pr` called successfully — merge request enqueued. The ticket work is complete:

- **`src/scriptorium/journal.nim`**: New module with `beginJournalTransition`, `executeJournalSteps`, `completeJournalTransition`, `replayOrRollbackJournal`, and `journalExists` procs implementing the write-ahead journal protocol with SHA-1 content hashing.
- **`tests/test_journal.nim`**: Unit tests covering normal completion, all-applied replay, partially-applied replay, and none-applied rollback scenarios.
```

### Agent Stdout Tail
```text
**`src/scriptorium/journal.nim`**: New module with `beginJournalTransition`, `executeJournalSteps`, `completeJournalTransition`, `replayOrRollbackJournal`, and `journalExists` procs implementing the write-ahead journal protocol with SHA-1 content hashing.\n- **`tests/test_journal.nim`**: Unit tests covering normal completion, all-applied replay, partially-applied replay, and none-applied rollback scenarios.","stop_reason":"end_turn","session_id":"546ad19c-5181-4c95-948f-37046086b8f9","total_cost_usd":0.6310732499999999,"usage":{"input_tokens":33,"cache_creation_input_tokens":23605,"cache_read_input_tokens":749804,"output_tokens":4339,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":23605,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":33,"outputTokens":4339,"cacheReadInputTokens":749804,"cacheCreationInputTokens":23605,"webSearchRequests":0,"costUSD":0.6310732499999999,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"aee9f42d-0d51-4e45-9579-ee3a36b73876"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 1m48s
