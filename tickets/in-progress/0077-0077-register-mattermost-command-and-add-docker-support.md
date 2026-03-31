# 0077 Register mattermost command and add Docker support

**Area:** chat-bots
**Depends:** 0076

## Description

Wire up the Mattermost bot as a runnable command and add Docker Compose support.

### scriptorium.nim changes

1. **Import** — add `mattermost_bot` to the import list.
2. **Add `cmdMattermost` proc**:
   ```nim
   proc cmdMattermost() =
     ## Run the Mattermost bot.
     runMattermostBot(getCurrentDir())
   ```
3. **Add command case** — add `of "mattermost": cmdMattermost()` to the command dispatch.
4. **Update `Usage` string** — add `scriptorium mattermost     Run the Mattermost bot` line after the discord entry.

### docker-compose.yml changes

Add a `mattermost` service mirroring the existing `discord` service:

```yaml
  mattermost:
    init: true
    build:
      context: .
    volumes:
      - .:/workspace
      - ~/.aws:/home/scriptorium/.aws:ro
    working_dir: /workspace
    env_file: .env
    environment:
      - CLAUDE_CODE_USE_BEDROCK
      - AWS_PROFILE
      - AWS_REGION
    entrypoint: ["/app/scripts/entrypoint.sh"]
    command: ["mattermost"]
```

### .env.example changes

Add `MATTERMOST_TOKEN=` line with a comment:
```
# Mattermost bot access token
MATTERMOST_TOKEN=
```

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0077-0077-register-mattermost-command-and-add-docker-support
