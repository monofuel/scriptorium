# Orchestrator Run Loop

Covers the `scriptorium run` main polling loop, gating logic, and tick ordering.

## Scope

- `scriptorium run` starts the orchestrator polling loop, MCP HTTP server, and repository-backed logging.
- MCP endpoint from `scriptorium.json` `endpoints.local`, defaulting to `http://127.0.0.1:8097`.
- Continuous polling with idle sleep between ticks.
- Work gated by:
  - Existence of `scriptorium/plan` branch.
  - Healthy `master` (required quality targets `make test` and `make integration-test` pass in order on a `master` worktree).
  - Runnable `spec.md` (not blank, not the init placeholder).
- Non-runnable spec logs: `WAITING: no spec — run 'scriptorium plan'`.
- Restructured tick order (V13, §30 supersedes §3):
  1. Poll completed agents (managers + coders) via `checkCompletedAgents()`.
     - For completed managers: acquire plan lock, write tickets, commit, release. Log results.
     - For completed coders: handle as before (move ticket, queue merge, etc).
  2. Check backoff / health.
  3. Run architect (sequential, if spec changed). Must complete before managers are spawned.
  4. Read areas needing tickets (brief plan lock).
  5. For each area needing tickets, if slots available, start a manager agent.
  6. For each assignable ticket, if slots available, start a coding agent.
  7. Process at most one merge-queue item.
  8. Sleep.
- Managers prioritized over coders when slots are scarce, since manager completions unblock future coding work.
- Managers and coders interleaved across ticks — no barrier between phases. If a manager finishes and produces tickets while another manager is running, those tickets can be assigned to coding agents on the next tick.
- When `maxAgents` is 1, behavior collapses to sequential execution as before.
- Tick must not block on a single agent completing when running in parallel mode — check for completable agents, start new agents, and continue other tick phases (detail in parallel-execution area).
- `master` health cached by `master` HEAD commit, recomputed only when `master` changes.
- `master` health cache persisted to `health/cache.json` on the plan branch for cross-session persistence (V4, §22, see health-cache area).
- Narrow plan branch locking (V13, §31):
  - Reading areas: brief lock to snapshot area content at start of tick.
  - Agent execution: no lock needed — managers produce ticket content in memory.
  - Writing tickets: main thread acquires lock per completed manager, writes, commits, releases.
  - Architect holds lock for full duration (sequential, runs before managers).
  - Detail in parallel-execution area.
- Tick summary line: at the end of each tick, log a single INFO-level summary capturing full system state (see observability area).
- Session summary: on shutdown (signal or idle exit), log aggregate session metrics (see observability area).

## Spec References

- Section 3: Orchestrator Run Loop.
- Section 13: Tick Summary Line (V3, detail in observability area).
- Section 16: Session Summary On Shutdown (V3, detail in observability area).
- Section 22: Commit Health Cache (V4, detail in health-cache area).
- Sections 23-24: Parallel Ticket Assignment and Concurrent Agent Execution (V5, detail in parallel-execution area).
- Section 30: Restructured Orchestrator Tick (V13, detail in parallel-execution area).
- Section 31: Narrow Plan Branch Locking (V13, detail in parallel-execution area).
