# 0105 — Add guildy dependency and create discord gateway module with CLI command

**Area:** discord
**Depends:** 0103

## Description

Add the `guildy` library as a dependency, create the core `src/scriptorium/discord_bot.nim` module with the Discord gateway connection, and wire the `scriptorium discord` CLI command.

### Requirements

1. **Add guildy dependency**: Run `nimby add https://github.com/monofuel/guildy` to add guildy to the project. This updates `nimby.lock`.

2. **Create `src/scriptorium/discord_bot.nim`** with:
   - A `runDiscordBot*(repoPath: string)` proc that:
     a. Reads `DISCORD_TOKEN` from environment. If unset or empty, print a clear error message (`"scriptorium: DISCORD_TOKEN environment variable is required"`) and `quit(1)`.
     b. Loads config via `loadConfig(repoPath)` to get `discord.channelId` and `discord.allowedUsers`.
     c. Validates that `channelId` is non-empty (quit with error if missing).
     d. Creates a guildy bot instance with the token.
     e. Registers a message handler that filters: ignore messages not in `channelId`, ignore messages from users not in `allowedUsers`, ignore bot messages.
     f. Starts the blocking gateway connection.
   - The message handler should be a skeleton for now — just log received messages. Slash command registration and architect invocation will be added in subsequent tickets.

3. **Wire CLI command** in `src/scriptorium.nim`:
   - Add `"discord"` case to the command dispatch.
   - Call `runDiscordBot(getCurrentDir())`.
   - Add `discord_bot` to imports.
   - Update the `Usage` string to include: `scriptorium discord          Start the Discord bot`.

### Notes

- guildy is from `github.com/monofuel/guildy` — a Discord bot API integration library.
- The gateway connection is blocking (the process runs until terminated).
- Follow Nim import conventions: one import block, bracket syntax, std/ first then libraries then local.
- Check guildy's API for bot creation and message handling patterns. Typical pattern: create a bot, add message handlers, call a `start` or `run` method.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0107-0105-add-guildy-dependency-and-create-discord-gateway-module-with-cli-command

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Multi-file change (new discord_bot.nim module + CLI wiring in scriptorium.nim + dependency addition) with moderate logic for message filtering, but straightforward patterns and no complex integration risk.
