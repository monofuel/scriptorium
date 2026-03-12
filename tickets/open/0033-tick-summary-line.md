# Tick Summary Line

**Area:** observability

## Description

Add a single INFO-level summary line at the end of each orchestrator tick capturing full system state.

## Current State

Individual component timings are logged at DEBUG level during the tick loop (architect, manager, coding agent, merge queue), but there is no consolidated INFO-level summary line per tick. Ticket counts (open/in-progress/done) are computed in `readOrchestratorStatus()` but not logged per tick.

## Requirements

- At the end of each tick in the main orchestrator loop, emit exactly one INFO-level log line.
- Required fields:
  - `architect`: `no-op`, `updated`, or `skipped`.
  - `manager`: `no-op`, `updated`, or `skipped`.
  - `coding`: ticket ID + status (`running`, `stalled`, `submitted`, `failed`) + wall time, or `idle`.
  - `merge`: `idle`, `processing`, or ticket ID being merged.
  - `open` / `in-progress` / `done`: current ticket counts.
- Format example: `tick 42 summary: architect=no-op manager=no-op coding=0031(running, 3m12s) merge=idle open=2 in-progress=1 done=14`
- Wall times must be human-readable (e.g., `3m12s`).
- Every tick produces exactly one summary line.

## Implementation Notes

- Add a helper proc to format durations as human-readable strings (e.g., seconds to `3m12s`).
- Gather component statuses from existing tick loop variables (`architectChanged`, `managerChanged`, agent result, merge queue state).
- Count ticket files in open/in-progress/done directories using existing `listMarkdownFiles()`.
- Insert the summary `logInfo()` call at the end of the tick loop body in `orchestrator.nim`.

## Spec References

- Section 13: Tick Summary Line (V3).
