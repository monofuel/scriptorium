# 0074 — Set logRoot for coding agent

**Area:** log-persistence

## Problem

The coding agent's `AgentRunRequest` does not set `logRoot`, so JSONL logs are written inside the ticket worktree under `<worktree>/.scriptorium/logs/<ticketId>/`. When the worktree is cleaned up after merge, these logs are lost.

## Task

In `src/scriptorium/coding_agent.nim`, in the `executeAssignedTicket` function (around line 176), add the `logRoot` field to the `AgentRunRequest`:

```nim
logRoot: repoPath / ManagedStateDirName / PlanLogDirName / "coder",
