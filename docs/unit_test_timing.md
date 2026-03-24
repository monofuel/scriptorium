# Test timing

Measured with warm Nim compilation cache on host (16 cores, 54GB RAM).
Execution time only (excludes compilation).

## Unit tests (`make test`)

Total: ~1.4s wall time (11 files, all run in parallel).

All unit tests run in under 1.3s individually. No git repos, no subprocesses.

## Integration tests (`make integration-test`)

| Test | Before | After | Notes |
|------|--------|-------|-------|
| integration_merge_queue.nim | 24.0s | 17.9s | Template repos + tmpfs |
| integration_orchestrator_flow.nim | 30.0+s | 30.0+s | Dominated by 30s idle sleep per tick |
| integration_ticket_assignment.nim | 3.8s | 1.9s | |
| integration_logging.nim | 4.4s | 3.1s | |
| integration_orchestrator_planning.nim | 2.5s | ~2s | |
| integration_recovery.nim | 1.75s | 1.4s | |
| integration_review.nim | 1.46s | 0.9s | |
| integration_scriptorium.nim | 0.70s | 0.34s | |
| integration_worktree_health.nim | 0.50s | ~0.3s | |
| integration_prior_work.nim | 0.47s | ~0.3s | |
| integration_journal.nim | 0.55s | ~0.3s | |
| integration_metrics.nim | 0.66s | ~0.4s | |

## Optimizations applied

- **Template repos**: `makeTestRepo` copies from a pre-initialized template
  instead of running `git init` + config + commit each time.
- **`makeInitializedTestRepo`**: Copies from a template with `runInit` already
  done (plan branch, AGENTS.md, Makefile, etc.), eliminating ~12 git spawns/test.
- **tmpfs**: `TMPDIR=/dev/shm` for integration tests (zero disk I/O).
- **Inline git config**: Write `.git/config` directly instead of `git config`.

## Remaining bottleneck

`integration_orchestrator_flow.nim` is dominated by `IdleBackoffSleepMs = 30_000`
(30s sleep between idle orchestrator ticks). Tests with multiple ticks that go
idle accumulate 30s+ of wall-clock sleep. This is architectural, not I/O-bound.
