# Change Default maxAgents From 1 To 4

**Area:** config-testing

## Problem

Per V13 §27, `concurrency.maxAgents` should default to 4 (changed from 1). The current implementation in `src/scriptorium/config.nim` defaults to 1.

## Requirements

1. In `src/scriptorium/config.nim`, change the `defaultConfig()` proc so `concurrency.maxAgents` defaults to 4 instead of 1.
2. Update unit tests in `tests/test_scriptorium.nim` that assert the default value of `maxAgents` — change expected value from 1 to 4.
3. Verify `make test` passes after the change.

## Files To Modify

- `src/scriptorium/config.nim`: Change default `maxAgents: 1` to `maxAgents: 4`.
- `tests/test_scriptorium.nim`: Update test assertions for default `maxAgents` value.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0064-default-maxagents-to-four

## Prediction
- predicted_difficulty: trivial
- predicted_duration_minutes: 5
- reasoning: Two-line change across two files (default value 1→4 and corresponding test assertion), no logic complexity or integration risk.
