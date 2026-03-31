# Chat Bot Integrations

Covers the Discord and Mattermost bot frontends to the Architect, including chat modes, slash commands, and shared infrastructure.

## Scope

**Shared chat infrastructure:**
- Chat modes selected by message prefix (transport-agnostic `parseChatMode`):
  - `plan:` — planning mode, can modify `spec.md` and create tickets on the plan branch (default when no prefix).
  - `ask:` — read-only Q&A with the Architect, no plan branch writes.
  - `do:` — full repo access mode for ad-hoc coding tasks.
- Slash commands (no LLM calls, read/write orchestrator state directly):
  - `/status` — ticket counts, active agents, in-progress elapsed times, blocked/waiting tickets, pause state.
  - `/queue` — merge queue contents and ticket lists.
  - `/pause` — write a pause flag; orchestrator stops picking up new work.
  - `/resume` — remove the pause flag.
- Shared chat logic (`chat_common.nim`) must be extracted so Discord and Mattermost bots share: mode parsing, status formatting, queue formatting, pause/resume handlers.
- Each chat message spawns a background thread to avoid blocking the gateway event loop.
- Both bots are standalone processes — the orchestrator does not know about them.
- Each message is stateless — no conversation history carried between messages.

**Discord bot (V12, §45):**
- `scriptorium discord` runs the Discord bot using the `guildy` library.
- Responses truncated to 2000 characters (Discord limit).
- Configuration in `scriptorium.json` under `discord`:
  - `enabled`: boolean.
  - `serverId`: Discord guild ID for guild-scoped slash command registration.
  - `channelId`: scopes the bot to a single channel.
  - `allowedUserIds`: list of Discord user IDs; messages from others are ignored.
- `DISCORD_TOKEN` environment variable is required; never stored in config.

**Mattermost bot (V12, §46):**
- `scriptorium mattermost` runs the Mattermost bot using the `mosty` library (`monofuel/mosty`).
- Connects to Mattermost WebSocket gateway via `mosty.startGateway`.
- Incoming posts filtered by channel ID, allowed user IDs, and bot's own messages (prevent self-reply loops).
- Responses posted via `mosty.createPost`, truncated to 16383 characters (Mattermost post limit).
- Slash commands detected by message prefix (not registered as server-side custom commands).
- Source file: `src/scriptorium/mattermost_bot.nim`, following the same structure as `discord_bot.nim`.
- `runMattermostBot` proc is the entry point, called from `cmdMattermost` in `scriptorium.nim`.
- Configuration in `scriptorium.json` under `mattermost`:
  - `enabled`: boolean.
  - `url`: Mattermost server base URL.
  - `channelId`: scopes the bot to a single channel.
  - `allowedUserIds`: list of Mattermost user IDs; messages from others are ignored.
- `MATTERMOST_TOKEN` environment variable provides the bot access token; never stored in config.

**Docker support:**
- A `mattermost` service in `docker-compose.yml`, mirroring the `discord` service structure.
- Mounts workspace and credentials, loads `.env` for `MATTERMOST_TOKEN`, runs `entrypoint.sh mattermost`.
- `.env.example` includes `MATTERMOST_TOKEN=` alongside existing `DISCORD_TOKEN=`.

## V12 Known Limitations

- Each message is stateless — no conversation history between messages.
- Bots connect to a single channel only; multi-channel support is out of scope.
- Mattermost slash commands are detected by message prefix, not registered as server-side custom commands.
- The `mosty` library is early-stage — API changes may require bot updates.

## Spec References

- Section 45: Discord Bot (V12).
- Section 46: Mattermost Bot (V12).
