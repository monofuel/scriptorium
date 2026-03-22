# v14 post-analysis

## Spec rewrite size limit

**Problem**: The `scriptorium plan` one-shot command failed to rewrite
`spec.md` (776 lines, ~48KB). The architect agent read the file, said "Now
I'll rewrite this as a flat topic-based blueprint", then ran out of output
tokens before actually performing the Write operation.

**Root cause**: Claude Code's `--print` mode has a max output tokens limit.
A full rewrite of a large spec requires reading the entire file (~48KB) into
context, then producing a similarly-sized output. The agent used most of its
output budget on thinking/planning and couldn't complete the write.

**Implications**: This is a structural limit on spec size. If the spec grows
beyond what an agent can rewrite in a single turn, the architect can no longer
restructure it. This affects:

- One-shot `scriptorium plan "<prompt>"` commands that request major rewrites
- Orchestrator-driven spec updates via `runPlanArchitectRequest`
- Any future "spec consolidation" automation

**Workarounds for now**:

1. **Interactive `scriptorium plan`**: Multi-turn sessions can break the
   rewrite into chunks — "rewrite sections 1-10", then "rewrite sections
   11-20", etc. Each turn stays within output limits.
2. **Manual edit via git worktree**: Edit `spec.md` directly on the plan
   branch using a worktree checkout. No agent needed.
3. **Multiple one-shot calls**: Break the rewrite into smaller operations —
   "remove all Known Limitations sections", then "merge V2 and V3 into
   topic headings", etc. Flaky but possible.

**Future considerations**:

- Should scriptorium enforce a spec size limit or warn when spec.md is
  getting too large?
- Could the architect be given a "chunked rewrite" mode where it rewrites
  one section at a time across multiple agent invocations?
- Should large specs be split into multiple files (e.g. `spec/cli.md`,
  `spec/orchestrator.md`) that the architect manages independently?
- The continuation/retry mechanism could help here — if the agent runs out
  of output mid-write, a retry could pick up where it left off. But the
  current retry logic is designed for coding agents, not planning.

## Missing area hash update in parallel manager path (bug)

**Problem**: After the v14 orchestrator started, managers ran for every area
but coding agents never started. The tick summary showed 38+ open tickets and
0 in-progress. Managers for the same areas kept being re-spawned on every tick,
consuming all 4 agent pool slots.

**Root cause**: The parallel manager completion handler in
`orchestrator.nim` (line ~162) wrote tickets to the plan branch but never
updated `tickets/.area-hashes`. The old synchronous `runManagerTicketsParallel`
function in `manager_agent.nim` updated hashes after all writes, but the new
per-completion path in the orchestrator tick loop did not.

Without the hash update, `areasNeedingTicketsInPlanPath()` returned the same
areas every tick, spawning duplicate managers that produced duplicate tickets.
The managers consumed all pool slots, starving coding agents.

**Fix** (commit 2d0e0fa):
1. Add `computeAllAreaHashes` + `writeAreaHashes` + commit after every
   manager completion in the orchestrator, even when 0 tickets are produced.
2. Add `isManagerRunningForArea()` check before spawning a manager to prevent
   duplicate in-flight managers for the same area.

**Impact**: ~62 duplicate tickets were created before the fix. Cleaned up by
deleting all open tickets and area hashes, then letting the fixed orchestrator
regenerate cleanly.

## Stale lock after container restart

**Problem**: After stopping the orchestrator container (`docker compose down`)
and restarting, the new container crashed immediately with:
`Error: unhandled exception: another planner/manager is active for /workspace [IOError]`

**Root cause**: The orchestrator uses a filesystem lock directory
(`.scriptorium/locks/repo.lock`) to prevent concurrent plan branch access.
When the container is killed (SIGKILL from `docker compose down` timeout, or
OOM), the lock directory is not cleaned up because the signal handler only
sets `shouldRun = false` and the graceful shutdown path may not complete.

Since the workspace is a bind-mount from the host, the lock persists across
container restarts. The `recoverFromCrash()` function tries to clean orphaned
worktrees but does so *inside* `withLockedPlanWorktree`, which fails because
the stale lock already exists.

**Workaround**: Manually delete `.scriptorium/locks/repo.lock` before
restarting the container. Also run `git worktree prune` and remove stale
entries under `.scriptorium/worktrees/`.

**Future fix**: The lock acquisition code should detect stale locks from
dead processes. Options:
- Write the PID into the lock directory and check if the PID is still alive
  on lock contention.
- Use `flock(2)` instead of `mkdir`-based locking — kernel-level locks are
  automatically released when the process dies.
- Add a `--force` flag to the orchestrator that clears stale locks on startup.
- The `recoverFromCrash()` function should run *before* acquiring any locks,
  or should handle the stale-lock case explicitly.

## Integration tests fail in docker container

**Problem**: The merge queue ran `make integration-test` as part of quality
gates, which failed with exit code 2. Every ticket that passed review was
reopened after merge failure, creating an infinite retry loop.

**Root cause**: The docker-compose (commit 64d668c) set
`ANTHROPIC_API_KEY=disabled` intending to force Bedrock-only usage. But
setting the key to a non-empty invalid string causes Claude Code to attempt
direct API auth with the garbage key instead of falling through to Bedrock.
The correct approach is to **unset** the keys entirely (`=`), not set them
to `"disabled"`.

**Initial workaround** (commit 512a62f): Removed `"integration-test"` from
`RequiredQualityTargets` to unblock the orchestrator run.

**Real fix**: Changed docker-compose to set `ANTHROPIC_API_KEY=` (empty)
instead of `ANTHROPIC_API_KEY=disabled`. Same for `OPENAI_API_KEY` and
`CODEX_API_KEY`. Restored `integration-test` to merge queue quality targets.

**Lesson**: When disabling env-var-based auth, unset the var entirely.
Setting it to a sentinel value can cause libraries to use it as a real
credential.

## Manager generates self-referential ticket dependencies

**Problem**: Ticket 0075 was generated with `**Depends:** 0074, 0075, 0076`
— it depends on itself. The cycle detector correctly flags this as a
dependency cycle, permanently blocking the ticket. Two other tickets (0074,
0082) that depend on 0075 are also permanently blocked.

**Root cause**: The manager agent generated the dependency list and
included the ticket's own ID. The manager prompt does not instruct the
agent to avoid self-references, and the orchestrator does not validate
dependency lists after ticket generation.

**Impact**: 3 of 10 v14 tickets were permanently blocked and never
executed. The blocked work (continuationPromptBuilder forwarding, audit
agent config, review prompt enforcement) would need to be done manually
or in a future orchestrator run.

**Future fix options**:
- Post-generation validation: the orchestrator should strip self-references
  from dependency lists before committing tickets.
- Manager prompt improvement: explicitly instruct the manager not to
  generate self-referential dependencies.
- Cycle detection could auto-repair by removing the self-reference edge
  rather than permanently blocking the ticket.
