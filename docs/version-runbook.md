# Version runbook

Step-by-step process for using scriptorium to implement its own version
updates, driven by `docs/v#.md` plan files.

Helper scripts in `scripts/` wrap the docker-compose commands for convenience.

## Prerequisites

- Docker and docker-compose installed
- API keys configured (`OPENAI_API_KEY`, `CODEX_API_KEY`, `ANTHROPIC_API_KEY`)
- Agent credentials mounted (`~/.codex`, `~/.claude`, `~/.claude.json`)
- A `docs/v#.md` plan file written and committed

## 1. Write the version plan

Create `docs/v<N>.md` with the plan for the new version. Include background,
concrete changes, file references, and a TODO checklist. Commit it to master.

```bash
vim docs/v12.md
git add docs/v12.md
git commit -m "docs: v12 plan"
git push origin master
```

## 2. Build the container

Rebuild the Docker image so it picks up the latest code and dependencies.

```bash
docker compose build
```

The build commit hash is embedded at compile time — pass `BUILD_COMMIT` as a
build arg for Docker builds, or it falls back to `git rev-parse` for local
builds.

## 3. Update the spec via the architect

- architect prompting instructions can be found at `./plan_prompting.md`
  - essentially:  be spec forward, not implementation forward
  - have the architect change the spec, not just append a list of changes to the end.

Use `scripts/plan.sh` to one-shot the architect with the new version plan:

```bash
./scripts/plan.sh "Read docs/v12.md and update the spec to include the planned changes."
```

The architect will read the plan file and your source tree, then update
`spec.md` on the plan branch.

If you need to review or iterate on the spec afterward, run interactively:

```bash
./scripts/plan.sh
```

Use `/show` to review the current spec, give feedback, and `/quit` when done.

Use `scripts/ask.sh` for read-only questions about the project without
modifying the spec:

```bash
./scripts/ask.sh
```

## 4. Commit any uncommitted work

The orchestrator caches master health per commit hash. If the previous commit
is cached as unhealthy (e.g. from a prior run), the orchestrator will skip
every tick without re-checking. Committing your changes advances HEAD to a new
hash that has no cached result, forcing a fresh health check.

```bash
git add -A && git commit -m "wip: pre-orchestrator checkpoint"
```

If the working tree is already clean, skip this step.

## 5. Start the orchestrator

Launch detached so the orchestrator runs in the background:

```bash
docker compose up -d
```

Or use `scripts/run.sh` to run in the foreground (blocks the terminal):

```bash
./scripts/run.sh
```

## 6. Monitor progress

### Container logs

Watch the container stdout (INFO level by default):

```bash
docker compose logs -f scriptorium
```

### Detailed logs inside the container

The orchestrator writes DEBUG-level logs to `<repo>/.scriptorium/logs/` (mounted
into the container via the workspace volume). To follow them:

```bash
tail -f .scriptorium/logs/orchestrator/run_*.log
```

Or from inside the container:

```bash
docker compose exec scriptorium bash -c 'tail -f /workspace/.scriptorium/logs/orchestrator/run_*.log'
```

### Check status

Run the status command to see ticket counts and active agents:

```bash
docker compose exec scriptorium /app/scriptorium status
```

List active worktrees:

```bash
docker compose exec scriptorium /app/scriptorium worktrees
```

## 7. What to watch for

- **Agents starting:** Look for `coding agent started` log lines with model
  and attempt info.
- **Tickets completing:** Look for `submit_pr called` followed by
  `merge queue entered`.
- **Tests passing:** Look for `merge queue: PASS` before merges to master.
- **Rate limits:** Look for `rate limit detected` — the orchestrator will
  back off automatically and reduce concurrency.
- **Stuck tickets:** Look for `tickets/stuck/` — these have failed too many
  times. Check the ticket file for failure notes.
- **Merge conflicts:** Look for `merge failed` — the ticket goes back for
  another coding attempt.

## 8. Stop the orchestrator

```bash
docker compose down
```

The orchestrator handles SIGTERM gracefully — it waits for running agents to
finish, logs a session summary, and exits cleanly.

## 9. Verify and tag

Once all TODO items in `docs/v<N>.md` are checked off:

1. Pull the latest master (the orchestrator has been merging into it):
   ```bash
   git pull origin master
   ```

2. Run tests locally to confirm:
   ```bash
   make test
   make integration-test
   ```

3. Bump the version in `scriptorium.nimble`.

4. Update the TODO checklist in `docs/v<N>.md` if any items were completed
   by the agents.

5. Commit, tag, and push:
   ```bash
   git add scriptorium.nimble docs/v<N>.md
   git commit -m "v<N>.0.0: <summary>"
   git tag v<N>.0.0
   git push origin master --tags
   ```

## Helper scripts

| Script | Purpose |
|--------|---------|
| `scripts/plan.sh` | Interactive or one-shot architect planning session |
| `scripts/ask.sh` | Read-only Q&A with the architect |
| `scripts/run.sh` | Start the orchestrator in the foreground |

All scripts `cd` to the repo root and use `docker compose run --rm`.

## Tips

- **Iterate on the spec:** If the agents aren't doing what you want, stop
  the orchestrator, run `./scripts/plan.sh` to refine the spec, then restart.
  The orchestrator picks up spec changes on the next tick.

- **Check agent output:** Each coding agent writes a log file. The path is
  logged when the agent starts. These contain the full agent stdout including
  tool calls and reasoning.

- **Parallel agents:** With `maxAgents > 1`, multiple coding agents run
  simultaneously on independent areas. Watch for merge conflicts if agents
  touch shared files.

- **Cost awareness:** Integration and e2e tests use real API calls. The
  orchestrator logs cumulative token usage in the session summary on shutdown.
