# Update area hashes after async manager completions in orchestrator

**Area:** agent-execution

When managers run in parallel (async) mode, the orchestrator writes tickets for completed managers but never updates area hashes. This means areas get re-ticketed on every subsequent tick even though their content hasn't changed.

## Current State

In `src/scriptorium/orchestrator.nim` (around lines 154-169), when a manager completion is processed:
- Tickets are written via `writeTicketsForAreaFromStrings` and committed.
- Area hashes in `tickets/.area-hashes` are never updated.

Compare with the serial path in `src/scriptorium/manager_agent.nim:runManagerForAreas` (lines 191-201), which correctly updates area hashes after all writes.

## Required Changes

1. In `src/scriptorium/orchestrator.nim`, after processing all manager completions that produced tickets in the completion polling loop, add an area hash update step:
   - After the `for completion in completions` loop, if any manager completions produced tickets (track with a boolean flag), acquire the plan worktree lock and update area hashes.
   - Use the same pattern as `runManagerForAreas`: call `computeAllAreaHashes`, `writeAreaHashes`, git add, and commit with `AreaHashesCommitMessage`.

2. The hash update should happen once per tick (not once per completion), to minimize lock acquisitions.

## Verification

- `make test` passes.
- After async manager completions, `tickets/.area-hashes` is updated with current area content hashes.
- Areas are not re-ticketed on subsequent ticks when their content hasn't changed.
