# 0091 Log WAITING no-spec message at INFO with deduplication

**Area:** orchestrator

## Problem

When the spec is not runnable (blank or init placeholder), `orchestrator.nim:263` logs the WAITING message at `logDebug` level. At the default INFO log level, operators never see this message and have no visibility into why the orchestrator is idle.

The unhealthy-master case (lines 196-201) already uses a dedup pattern: log once at WARN, suppress until state changes. The non-runnable spec case should follow the same pattern.

## Task

In `src/scriptorium/orchestrator.nim`:

1. Add a `lastSpecWaitingLogged` boolean (similar to `lastHealthLogged` in `MasterHealthState`) to track whether the WAITING message has been logged.
2. On the first tick where `hasRunnableSpec` returns false, log at INFO level: `WAITING: no spec — run 'scriptorium plan'`.
3. On subsequent ticks where spec remains non-runnable, skip the log (or log at DEBUG).
4. When spec becomes runnable again, reset the flag so the message can re-fire if spec reverts.

## Acceptance criteria

- First non-runnable-spec tick logs `WAITING: no spec — run 'scriptorium plan'` at INFO level.
- Subsequent non-runnable ticks do not repeat the INFO log.
- When spec becomes runnable and then non-runnable again, the INFO message fires once more.
- Existing tests pass. Add a unit test covering the dedup behavior.
````

````markdown
# 0092 Migrate orchestrator.nim format strings from fmt to &

**Area:** orchestrator

## Problem

`src/scriptorium/orchestrator.nim` uses `fmt` for format strings in ~20 places (lines 16, 155, 192, 195, 221, 250, 277, 278, 283, 284, 287, 327, 330, etc.). The project convention in CLAUDE.md and AGENTS.md requires `&` for format strings, not `fmt`. Additionally, some format strings call functions inline (e.g., `epochTime() - t0`) which should be assigned to variables first per convention.

## Task

In `src/scriptorium/orchestrator.nim`:

1. Replace all `fmt"..."` usages with `&"..."`.
2. For any format strings that call functions inline, extract the result to a local variable first, then interpolate.
3. Do not change any behavior — this is a mechanical style migration.

Example before:
```nim
logDebug(fmt"tick {ticks}: master health check took {epochTime() - t0:.1f}s, healthy={healthy}")

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0094-0091-log-waiting-no-spec-message-at-info-with-deduplication
