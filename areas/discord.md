# Discord Bot Integration

Covers the `scriptorium discord` command that runs a Discord bot as a frontend to the architect, independent of the orchestrator.

## Scope

- `scriptorium discord` starts a blocking guildy gateway connection.
- Bot is scoped to a single channel (`discord.channelId` in config). Messages in other channels are ignored.
- Only users listed in `discord.allowedUsers` may interact. Messages from other users are ignored.
- Bot token read from `DISCORD_TOKEN` environment variable. If unset, the command must fail with a clear error. Token is never stored in config.
- Bot process is independent of `scriptorium run`. Both may run simultaneously; plan branch coordination uses the transactional commit lock (§17).

### Slash Commands

Four slash commands that require no LLM calls — they read or write local state directly:

- `/status` — Report current iteration, tickets in flight, merge queue contents, and whether the orchestrator is running.
- `/queue` — Show the current ticket queue with statuses.
- `/pause` — Write a pause flag to `.scriptorium/`. The orchestrator stops picking up new work; in-flight agents finish but nothing new starts.
- `/resume` — Remove the pause flag.

### Chat Messages

- Non-slash messages from allowed users in the configured channel are sent to the architect as standalone invocations.
- Each message is stateless — no Discord chat history is carried between messages.
- The architect's response is posted back to the channel.
- If the architect modifies `spec.md` or creates tickets, it does so on the plan branch as normal, using the transactional commit lock.
- The architect invocation follows the same pattern as `scriptorium plan` one-shot mode: managed plan worktree, repo-root context, write allowlist of `spec.md` only.

### Dependencies

- guildy for the Discord gateway connection.
- No new dependencies for the orchestrator or any other existing component.

## Spec References

- Section 23: Discord Bot Integration.
- Section 17: Plan Branch Locking (transactional commit lock shared with bot process).
- Section 16: Config, Logging, And CI (discord config keys).
