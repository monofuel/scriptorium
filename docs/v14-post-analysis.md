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

**Root cause**: The docker-compose sets `ANTHROPIC_API_KEY=disabled` and
`OPENAI_API_KEY=disabled` to force Bedrock-only usage. However, the
integration tests check `getEnv("ANTHROPIC_API_KEY").len > 0` — the string
`"disabled"` has length > 0, so the test proceeds past the skip guard but
then fails when the actual API call uses an invalid key.

Additionally, even with working credentials, running full integration tests
(which make real API calls) on every merge is expensive and slow.

**Fix** (commit 512a62f): Remove `"integration-test"` from
`RequiredQualityTargets` in `merge_queue.nim`. Unit tests (`make test`) are
sufficient for merge queue validation. Integration tests remain available
via `make integration-test` for manual/CI use.

**Future considerations**:
- The integration test skip guard should check for `"disabled"` as an
  invalid key value, not just check string length.
- Consider a `scriptorium.json` config for merge queue quality targets so
  projects can choose what to run.
- The health check also uses `RequiredQualityTargets` — with integration
  tests removed, the health cache entries will have 0 for
  `integration_test_*` fields.
