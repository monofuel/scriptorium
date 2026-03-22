# 0076 — Set logRoot for prediction agent

**Area:** log-persistence

## Problem

The prediction agent's `AgentRunRequest` in `src/scriptorium/coding_agent.nim` (around line 78) does not set `logRoot`. Currently it uses ticketId `"{ticketId}-prediction"` which causes logs to land at `<repoPath>/.scriptorium/logs/{ticketId}-prediction/` (the default fallback). The area spec requires `prediction/<ticketId>/` structure instead.

## Task

In `src/scriptorium/coding_agent.nim`, in `predictTicketDifficulty` (around line 78):

1. Add the `logRoot` field to the `AgentRunRequest`:
   ```nim
   logRoot: repoPath / ManagedStateDirName / PlanLogDirName / "prediction",

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0078-0076-set-logroot-for-prediction-agent

## Prediction
- predicted_difficulty: trivial
- predicted_duration_minutes: 5
- reasoning: Single-line addition of a logRoot field to an existing AgentRunRequest struct in one file, no logic changes or tests needed.
