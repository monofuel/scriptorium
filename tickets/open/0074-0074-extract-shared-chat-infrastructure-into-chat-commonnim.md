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
