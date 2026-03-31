# 0074 Extract shared chat infrastructure into chat_common.nim

**Area:** chat-bots

## Description

Extract transport-agnostic chat logic from `src/scriptorium/discord_bot.nim` into a new `src/scriptorium/chat_common.nim` module so that both the Discord and Mattermost bots can share it.

### What to extract

Move the following from `discord_bot.nim` into `chat_common.nim`:

1. **`ChatMode` enum** — `chatModePlan`, `chatModeAsk`, `chatModeDo`.
2. **`parseChatMode` proc** — parses `ask:`, `plan:`, `do:` prefixes. Default: `chatModePlan`.
3. **`truncateMessage` proc** — generalize to accept a `limit: int` parameter instead of using the hardcoded `DiscordMessageLimit` constant. Discord will pass 2000, Mattermost will pass 16383.
4. **`formatStatusMessage` proc** — builds the `/status` response string from orchestrator state.
5. **`formatQueueMessage` proc** — builds the `/queue` response string from plan branch state.
6. **`handlePause` proc** — handles the `/pause` command.
7. **`handleResume` proc** — handles the `/resume` command.

### Update discord_bot.nim

After extraction, update `discord_bot.nim` to import from `chat_common` and use the shared procs. The Discord-specific `truncateMessage` wrapper can call `truncateMessage(msg, DiscordMessageLimit)`. Remove the moved code from `discord_bot.nim`.

Keep Discord-specific code in `discord_bot.nim`: gateway connection, slash command registration, `guildy` imports, `postChannelMessage` calls, thread spawning, interaction handling.

### Unit tests

Add `tests/test_chat_common.nim` with tests for:
- `parseChatMode` — all prefixes (`ask:`, `plan:`, `do:`), default (no prefix), case insensitivity, whitespace handling.
- `truncateMessage` — under limit, at limit, over limit, marker appended correctly.

### Coding conventions

- Follow Nim import style: one block, bracket syntax, std/ first.
- Doc comments (`##`) on every proc.
- Constants use PascalCase.
- Use `&` for format strings, not `fmt`.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0074-0074-extract-shared-chat-infrastructure-into-chat-commonnim

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Extracting existing procs into a new module with updated imports across two files plus new unit tests is straightforward multi-file refactoring with low integration risk, one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0074/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0074/attempt-01.last_message.txt\n
### Agent Last Message
```text
Work complete. The PR has been submitted to the merge queue.

**Summary of changes:**

- **New `src/scriptorium/chat_common.nim`** — contains `ChatMode` enum, `parseChatMode`, `truncateMessage` (with `limit` parameter), `formatStatusMessage`, `formatQueueMessage`, `handlePause`, and `handleResume`
- **Updated `src/scriptorium/discord_bot.nim`** — imports from `chat_common`, removed moved code, local `truncateMessage` wrapper calls `chat_common.truncateMessage(msg, DiscordMessageLimit)`
- **New `tests/test_chat_common.nim`** — 10 tests covering all `parseChatMode` cases (prefixes, default, case insensitivity, whitespace) and `truncateMessage` (under/at/over limit, custom limit)
```

### Agent Stdout Tail
```text
handleResume`\n- **Updated `src/scriptorium/discord_bot.nim`** — imports from `chat_common`, removed moved code, local `truncateMessage` wrapper calls `chat_common.truncateMessage(msg, DiscordMessageLimit)`\n- **New `tests/test_chat_common.nim`** — 10 tests covering all `parseChatMode` cases (prefixes, default, case insensitivity, whitespace) and `truncateMessage` (under/at/over limit, custom limit)","stop_reason":"end_turn","session_id":"f675b72c-638a-4f89-8982-a8f72bb73ac2","total_cost_usd":1.1953779999999998,"usage":{"input_tokens":35,"cache_creation_input_tokens":45502,"cache_read_input_tokens":1208631,"output_tokens":12260,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":45502,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":35,"outputTokens":12260,"cacheReadInputTokens":1208631,"cacheCreationInputTokens":45502,"webSearchRequests":0,"costUSD":1.1953779999999998,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"12a0d918-d392-4cb2-849f-e5c98d72d69e"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 51s

**Review Reasoning:** Let me review the changes against the ticket requirements and project conventions.
The changes look clean. Let me verify the review is complete by checking one more thing — whether `discord_bot.nim` still uses all its remaining imports.
All imports are still used. The review is complete — this is a clean, faithful extraction.


**Review summary:**

- **Convention compliance:** All conventions followed — single import block with bracket syntax, std/ first then local, PascalCase constants, camelCase variables, doc comments on every proc with complete sentences and punctuation, grouped const/let/var blocks.
- **Spec compliance:** All 7 items from the ticket extracted correctly (ChatMode, parseChatMode, truncateMessage with limit parameter, formatStatusMessage, formatQueueMessage, handlePause, handleResume). Discord wrapper calls `chat_common.truncateMessage(msg, DiscordMessageLimit)` as specified. Discord-specific code remains in `discord_bot.nim`.
- **Code quality:** No unused imports, no dead code, no leftover artifacts. The extraction is a faithful move with no behavioral changes. `TruncatedMarker` correctly exported for test and future Mattermost use.
- **Tests:** All required cases covered — parseChatMode (all prefixes, default, case insensitivity, whitespace) and truncateMessage (under/at/over limit, custom limit for Mattermost).
Review approved. The extraction is clean, complete, and follows all project conventions.
