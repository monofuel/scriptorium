# 0106 — Implement /status and /queue slash commands

**Area:** discord
**Depends:** 0105

## Description

Register and implement the `/status` and `/queue` Discord slash commands in the discord bot module. These are read-only commands that query local state — no LLM calls.

### Requirements

1. **Register slash commands** with guildy when the bot starts. Both commands take no arguments.

2. **`/status` command handler**:
   - Read orchestrator status using `readOrchestratorStatus(repoPath)` from `output_formatting.nim` (same function used by `cmdStatus` in `scriptorium.nim`).
   - Format a Discord message with:
     - Open / In-Progress / Done ticket counts
     - Active agent ticket (if any)
     - In-progress ticket elapsed times
     - Whether the orchestrator is running (check `.scriptorium/orchestrator.pid` — use the PID liveness check from `lock_management.nim` or just check file existence)
     - Whether paused (check `isPaused(repoPath)` from ticket 0104)
   - Post the formatted message back to the channel.

3. **`/queue` command handler**:
   - Read the merge queue contents from the plan branch. Use `listMergeQueueItems` or equivalent from `merge_queue.nim` / plan branch state.
   - Read open and in-progress ticket lists from plan branch directories (`tickets/open/`, `tickets/in-progress/`).
   - Format a Discord message showing ticket IDs and their statuses.
   - Post back to the channel.

4. Both commands should respond within Discord's interaction timeout. Since they only read local files and git state, this should be fast.

### Notes

- The `readOrchestratorStatus` proc is already used by the CLI `status` command — reuse it.
- For reading plan branch ticket state, use `withLockedPlanWorktree` from `lock_management.nim` to safely access the plan worktree.
- Discord messages have a 2000-character limit. Truncate long output if necessary.
- Use `&` for format strings, not `fmt`.
