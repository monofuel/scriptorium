# 0089 Enforce staggered coding agent start in parallel mode

**Area:** orchestrator

## Problem

The area spec requires "at most 1 new coding agent per tick — staggered start rule" in parallel mode. However, `orchestrator.nim:291-296` calls `assignOpenTickets(repoPath, slotsAvailable)` where `slotsAvailable` can be greater than 1, then starts all returned assignments in a single tick. This violates the staggered start rule and can overwhelm the system with simultaneous agent startups.

## Task

In `src/scriptorium/orchestrator.nim`, limit the number of new coding agents started per tick to 1 when `maxAgents > 1`. The simplest fix is to cap the argument to `assignOpenTickets` at 1:

```nim
let assignments = assignOpenTickets(repoPath, 1)

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0092-0089-enforce-staggered-coding-agent-start-in-parallel-mode

## Prediction
- predicted_difficulty: trivial
- predicted_duration_minutes: 5
- reasoning: Single-line change capping assignOpenTickets argument to 1, isolated to one location in orchestrator.nim with no cross-module impact.
