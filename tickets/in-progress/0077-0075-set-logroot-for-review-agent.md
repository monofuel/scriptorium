# 0075 — Set logRoot for review agent

**Area:** log-persistence

## Problem

The review agent's `AgentRunRequest` in `src/scriptorium/merge_queue.nim` (around line 213) does not set `logRoot`, so JSONL logs are written inside the ticket worktree. These logs are lost when the worktree is cleaned up after merge.

## Task

In `src/scriptorium/merge_queue.nim`, in the `runReviewAgent` function, add the `logRoot` field to the `AgentRunRequest`:

```nim
logRoot: repoPath / ManagedStateDirName / PlanLogDirName / "review",

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0077-0075-set-logroot-for-review-agent
