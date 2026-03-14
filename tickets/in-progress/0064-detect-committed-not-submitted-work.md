# Detect Committed-But-Not-Submitted Work

**Area:** agent-execution

Implement detection of prior commits on the ticket branch that were not submitted via `submit_pr`, as specified in V8, §34.

## Requirements

At the start of each coding agent attempt (including the first), check whether the ticket branch has commits ahead of `master`:

1. **Detection:** Run `git log master..<branch> --oneline` in the worktree to find commits ahead of master.
2. **When prior work detected:**
   - Log: `ticket <id>: found <n> committed changes from prior attempt, agent will continue from branch tip`.
   - Include a note in the agent prompt informing the agent that prior work exists and it should review existing changes before proceeding.
3. **Do not reset the branch** — the agent works from the branch tip, building on prior commits.

## Implementation Notes

- Add detection logic in `executeAssignedTicket` in `coding_agent.nim`, before building the prompt for each attempt.
- Use `runCommandCapture` to run `git log master..<branch> --oneline` and count lines.
- Extend `buildCodingAgentPrompt` (or create a wrapper) to accept an optional prior-work note that gets prepended/appended to the prompt.
- The initial prompt and continuation prompts should both include the prior-work note when applicable.

## Acceptance Criteria

- Prior commits on the ticket branch are detected at each attempt start.
- Log message emitted with correct commit count.
- Agent prompt includes prior-work awareness note when commits exist.
- No branch reset occurs — agent continues from branch tip.
- Unit tests cover: no prior work, prior work detected with correct count.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0064-detect-committed-not-submitted-work

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Single-file change in coding_agent.nim adding a git log check and string interpolation into the prompt builder, with straightforward unit tests for line counting logic.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0064-detect-committed-not-submitted-work/.scriptorium/logs/0064/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0064-detect-committed-not-submitted-work/.scriptorium/logs/0064/attempt-01.last_message.txt\n
### Agent Last Message
```text
All work is committed. The `submit_pr` MCP tool is not available in this environment (it's served by the orchestrator's MCP server at runtime). Here's a summary of what was implemented:

**Changes made:**

1. **`src/scriptorium/coding_agent.nim`** - Added `detectPriorWork` proc that runs `git log master..HEAD --oneline` in the worktree and returns the count of commits ahead of master. Wired it into `executeAssignedTicket` before building the prompt, passing a prior-work note when commits are found.

2. **`src/scriptorium/prompt_builders.nim`** - Extended `buildCodingAgentPrompt` with an optional `priorWorkNote` parameter (default `""`). When non-empty, the note is appended to the prompt.

3. **`tests/test_prior_work.nim`** - Four unit tests covering:
   - No prior commits returns zero
   - Prior commits detected with correct count (2 commits)
   - No prior work note leaves prompt unchanged
   - Prior work note is appended to prompt
```

### Agent Stdout Tail
```text
ompt_builders.nim`** - Extended `buildCodingAgentPrompt` with an optional `priorWorkNote` parameter (default `\"\"`). When non-empty, the note is appended to the prompt.\n\n3. **`tests/test_prior_work.nim`** - Four unit tests covering:\n   - No prior commits returns zero\n   - Prior commits detected with correct count (2 commits)\n   - No prior work note leaves prompt unchanged\n   - Prior work note is appended to prompt","stop_reason":"end_turn","session_id":"2a1e24e4-7e25-4f0e-9622-7d0e6a9a6f57","total_cost_usd":1.49365375,"usage":{"input_tokens":42,"cache_creation_input_tokens":54495,"cache_read_input_tokens":1921350,"output_tokens":7687,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":54495,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":42,"outputTokens":7687,"cacheReadInputTokens":1921350,"cacheCreationInputTokens":54495,"webSearchRequests":0,"costUSD":1.49365375,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"d0644c28-04c1-4608-b036-a3a3e2342a2a"}
```

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 2\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0064-detect-committed-not-submitted-work/.scriptorium/logs/0064/attempt-02.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0064-detect-committed-not-submitted-work/.scriptorium/logs/0064/attempt-02.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` MCP tool has been called successfully. The response confirms: **"Merge request enqueued."**

The previous attempt had already implemented all the required changes and tests were passing. The work includes:
- `detectPriorWork` proc that runs `git log master..<branch> --oneline` to find commits ahead of master
- Integration into `executeAssignedTicket` before prompt building
- Extended `buildCodingAgentPrompt` to accept an optional prior-work note
- Unit tests covering no prior work and prior work detected with correct count
```

### Agent Stdout Tail
```text
ady implemented all the required changes and tests were passing. The work includes:\n- `detectPriorWork` proc that runs `git log master..<branch> --oneline` to find commits ahead of master\n- Integration into `executeAssignedTicket` before prompt building\n- Extended `buildCodingAgentPrompt` to accept an optional prior-work note\n- Unit tests covering no prior work and prior work detected with correct count","stop_reason":"end_turn","session_id":"a5b649fa-de3a-4c12-be94-a225a792b474","total_cost_usd":0.5320552500000001,"usage":{"input_tokens":28,"cache_creation_input_tokens":24017,"cache_read_input_tokens":587618,"output_tokens":3520,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":24017,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":28,"outputTokens":3520,"cacheReadInputTokens":587618,"cacheCreationInputTokens":24017,"webSearchRequests":0,"costUSD":0.5320552500000001,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"a634aae5-1204-4661-85b0-60bb6e5acf9c"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 1m19s
