# Narrow Plan Branch Locking

**Area:** parallel-execution

**Depends:** 0071

## Problem

V13 §31 requires narrow plan branch locking instead of holding the lock for the entire manager batch. With per-area concurrent managers, locking should be brief and targeted.

## Requirements

1. **Reading areas**: Brief lock to snapshot area content at start of tick. Done once for all areas, not per-manager. Lock acquired, area files read into memory, lock released.
2. **Agent execution**: No lock needed. Manager agents run in threads and produce ticket content in memory.
3. **Writing tickets**: Main thread acquires lock per completed manager, writes tickets for that manager, commits, releases. Each completed manager's write is a separate short lock acquisition.
4. **Architect**: Still holds lock for full duration (reads spec and writes area files). Acceptable because architect is sequential and runs before managers.
5. Ensure the existing `planWorktreeLock` (in `orchestrator.nim`) is used consistently for all plan branch access.
6. Verify that no agent threads touch the plan worktree directly — only the orchestrator main thread writes.
7. `make test` must pass.

## Notes

- The `planWorktreeLock` already exists in `src/scriptorium/orchestrator.nim`.
- This replaces the model where the lock was held for the entire manager batch execution.
- The lock management module is at `src/scriptorium/lock_management.nim`.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0072-narrow-plan-branch-locking

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Refactors lock acquisition boundaries in orchestrator.nim around existing planWorktreeLock — primarily restructuring when locks are acquired/released rather than adding new mechanisms, but concurrency locking changes carry moderate integration risk requiring careful testing.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/worktrees/tickets/0072-narrow-plan-branch-locking/.scriptorium/logs/0072/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/worktrees/tickets/0072-narrow-plan-branch-locking/.scriptorium/logs/0072/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Here's a summary of the changes:

**5 files changed:**

1. **`src/scriptorium/manager_agent.nim`** — `executeManagerForArea` now uses `repoPath` as working directory (not `planPath`), removed plan worktree fallback. `runManagerForAreas` restructured for narrow locking: brief lock to snapshot areas → no lock during agent execution → brief lock per completed manager to write tickets.

2. **`src/scriptorium/prompt_builders.nim`** — Removed `planPath` parameter from `buildManagerTicketsPrompt`.

3. **`src/scriptorium/prompts/manager_tickets.md`** — Updated prompt to instruct agents to output tickets as fenced markdown blocks instead of writing files to the plan worktree.

4. **`tests/test_manager_agent.nim`** — Updated test calls to match new `buildManagerTicketsPrompt` signature.

5. **`tests/test_prompt_catalog.nim`** — Removed check for `WORKTREE_PATH` in manager template.
```

### Agent Stdout Tail
```text
mpt`.\n\n3. **`src/scriptorium/prompts/manager_tickets.md`** — Updated prompt to instruct agents to output tickets as fenced markdown blocks instead of writing files to the plan worktree.\n\n4. **`tests/test_manager_agent.nim`** — Updated test calls to match new `buildManagerTicketsPrompt` signature.\n\n5. **`tests/test_prompt_catalog.nim`** — Removed check for `WORKTREE_PATH` in manager template.","stop_reason":"end_turn","session_id":"2e20f3f9-762d-44f4-b346-55933f59a757","total_cost_usd":2.032117,"usage":{"input_tokens":9669,"cache_creation_input_tokens":77306,"cache_read_input_tokens":2244269,"output_tokens":15139,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":77306},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":9669,"outputTokens":15139,"cacheReadInputTokens":2244269,"cacheCreationInputTokens":77306,"webSearchRequests":0,"costUSD":2.032117,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"b0c40528-8c61-4fe0-b2b0-61d960d38539"}
```
