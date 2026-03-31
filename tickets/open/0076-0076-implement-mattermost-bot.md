# 0076 Implement Mattermost bot

**Area:** chat-bots
**Depends:** 0074, 0075

## Description

Create `src/scriptorium/mattermost_bot.nim` implementing the Mattermost bot frontend, following the same structure as `discord_bot.nim`.

Use the **`mosty`** library (`monofuel/mosty`) for Mattermost API and WebSocket gateway connectivity. The library is already available via nimby.

### Implementation

Create `runMattermostBot*(repoPath: string)` as the entry point proc:

1. **Token check** — read `MATTERMOST_TOKEN` from env. Exit with error if empty.
2. **Config loading** — load `MattermostConfig` from `scriptorium.json`. Exit if `channelId` is empty. Read `url` for server base URL.
3. **Gateway connection** — use `mosty.startGateway` to connect to the Mattermost WebSocket gateway.
4. **Message filtering** — filter incoming posts by:
   - Channel ID must match `channelId`.
   - Skip bot's own messages (prevent self-reply loops) by checking the post's user ID against the bot's own user ID.
   - If `allowedUserIds` is non-empty, only accept messages from listed user IDs.
5. **Slash command detection** — detect `/status`, `/queue`, `/pause`, `/resume` by checking if the message starts with these prefixes. These are NOT registered as server-side Mattermost commands — just message prefix detection.
6. **Chat mode routing** — use `parseChatMode` from `chat_common` to route messages to the appropriate handler (`handleChatMessage`, `handleAskMessage`, `handleDoMessage`).
7. **Response posting** — use `mosty.createPost` to post responses back to the channel.
8. **Message truncation** — truncate responses to 16383 characters (Mattermost post limit) using `truncateMessage` from `chat_common`.
9. **Background threading** — each message spawns a background thread to avoid blocking the gateway event loop, same pattern as `discord_bot.nim`.

### Chat message handlers

The three chat handlers (`handleChatMessage`, `handleAskMessage`, `handleDoMessage`) follow the same logic as in `discord_bot.nim` but use `mosty.createPost` instead of `guildy.postChannelMessage`. Import shared logic from `chat_common`.

### Constants

```nim
const
  MattermostMessageLimit = 16383
  MattermostChatTicketId = "mattermost-chat"
```

### Coding conventions

- Follow Nim import style: one block, bracket syntax, std/ first.
- Doc comments (`##`) on every proc.
- Use `&` for format strings, not `fmt`.
- Do not use try/catch unless absolutely necessary. Let errors bubble up.
