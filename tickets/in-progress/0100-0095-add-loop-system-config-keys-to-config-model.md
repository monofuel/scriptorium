<!-- ticket: 0095-add-loop-config-keys.md -->
# 0095 — Add loop system config keys to Config model

**Area:** config-testing

## Description

The spec (Section 22: Loop System) defines four config keys under `loop.*` that are
not yet present in the `Config` type or `loadConfig` proc. Add them so the
orchestrator (and future loop implementation) can read them from `scriptorium.json`.

### Required changes

**`src/scriptorium/config.nim`**

1. Add a new `LoopConfig` object type:

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0100-0095-add-loop-system-config-keys-to-config-model

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 11
- reasoning: Adding a new LoopConfig object type and four fields to the Config model with loadConfig parsing is a single-file change with straightforward struct/deserialization work plus unit tests.
