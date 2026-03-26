# Auto-Reload: Push, Tag, and Restart

Design doc for enabling scriptorium to push its own work to origin, tag releases, and trigger container rebuilds automatically.

## Problem

After the orchestrator finishes a batch of work (all tickets merged to local master), it sits idle. Currently there is no mechanism to:

1. Push local master to origin
2. Trigger a Docker image rebuild with the new code
3. Restart the containers with the updated image

The human must manually `git push origin master` from the host after every run.

## Design

### Tag-driven restarts

The architect agent controls when a restart happens by pushing a git tag. Tags are a deliberate, versioned signal — not just "I'm idle" but "I've reached a releasable state." A host-side watcher script polls for new tags and triggers rebuild + restart when one appears.

### Flow

1. Orchestrator runs, tickets are coded/reviewed/merged to local master.
2. Queue drains, orchestrator becomes idle.
3. Architect recognizes a milestone — bumps version in nimble, commits, tags, pushes to origin (both commits and tag).
4. Host-side watcher detects new tag, triggers `docker compose build && docker compose up -d`.
5. Orchestrator boots fresh on the new image, picks up any remaining or new work.

### Why tags (not idle detection)

Idle detection alone would trigger on every quiet moment. Tags let the architect make a judgment call:

- "I finished the dashboard feature, tag v18.0.0" — restart.
- "I only finished config tickets, not worth a restart yet" — keep going.
- "Tests are flaky on this batch, fix first before tagging" — no restart.

The architect becomes the release manager, which is the role it already plays.

### Timing is self-regulating

The watcher poll interval doesn't need to be clever because the architect controls when tags appear:

- Fast work (easy tickets): architect might tag every 20-30 minutes.
- Slow work (hard tickets, retries): might be hours between tags.
- No work: no new tags, watcher does nothing.

A poll interval of 2-5 minutes checking for new tags is effectively free.

## Components

### 1. Push credentials

The orchestrator container needs push access to origin. Options:

- **Gitea deploy token** (preferred): Scoped HTTPS token for the repo. Mount as env var or secret file. Less risk than SSH keys.
- **SSH key mount**: Mount `~/.ssh` read-only into the container. Broader access surface.

### 2. Architect push behavior

When the orchestrator is idle and the architect determines a milestone is reached:

1. Bump version in `scriptorium.nimble`.
2. Commit: `vX.Y.Z: <summary of batch>`.
3. Tag: `vX.Y.Z`.
4. `git push origin master --tags`.

The architect already understands versioning conventions (it produced v17.0 through v17.2 tags).

### 3. Host-side watcher script

Conceptual logic:

```
LAST_TAG=$(current deployed tag)
while true:
  git fetch --tags origin
  LATEST_TAG=$(git describe --tags --abbrev=0 origin/master)
  if LATEST_TAG != LAST_TAG:
    docker compose build
    docker compose down
    docker compose up -d
    LAST_TAG=$LATEST_TAG
  sleep 3m
```

This could be a systemd unit, a cron job, or a simple bash loop running in a tmux/screen session.

### 4. Graceful shutdown

Before restarting, the watcher should allow the orchestrator to clean up:

- `docker compose down` sends SIGTERM. The orchestrator should handle this gracefully (stop accepting new tickets, let running agents finish or checkpoint).
- Journal-based recovery means interrupted tickets will retry on next boot.
- Discord bot reconnects automatically via guildy's gateway reconnect.

## Edge cases

### Rebuild while agents are mid-work

If the architect tags while coding agents are still running (shouldn't happen if it waits for idle, but possible with concurrent Discord commands), the journal ensures no work is lost. Tickets in progress will be detected as interrupted on next boot and retried.

### Tag but tests are broken

The merge queue already runs `make test` before merging, so tagged code should be tested. As extra safety, the watcher could run `make test` on the new code before swapping images — but this adds build time on the host.

### Discord bot restart

Both services share the same Docker image. A rebuild restarts both. The discord bot reconnects automatically. Downtime is limited to the build duration (~2-3 minutes). To minimize this:

- Build the new image first (`docker compose build`), then restart (`docker compose up -d`). The restart itself is near-instant.
- Future: separate Dockerfiles so discord can run independently.

### Multiple rapid tags

If the architect tags twice before the watcher polls, the watcher just sees the latest tag and does one rebuild. No wasted cycles.

## Future considerations

- **Gitea CI integration**: Instead of a host watcher, let Gitea Actions build and push images to a registry. Then use Watchtower or similar to auto-pull new images. More infrastructure but more standard.
- **Rollback**: If a new image fails to start, the watcher could detect the container exiting and roll back to the previous tag/image.
- **Split images**: Separate Dockerfiles for orchestrator and discord bot so they can be versioned and restarted independently.
- **Idle timeout**: If the architect doesn't tag after being idle for a configurable period, auto-push commits (without tag) so work isn't lost even if the architect doesn't deem it milestone-worthy.
