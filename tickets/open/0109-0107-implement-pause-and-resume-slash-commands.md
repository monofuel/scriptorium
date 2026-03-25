# 0107 — Implement /pause and /resume slash commands

**Area:** discord
**Depends:** 0104, 0105

## Description

Register and implement the `/pause` and `/resume` Discord slash commands in the discord bot module.

### Requirements

1. **Register `/pause` and `/resume`** as slash commands with guildy (no arguments).

2. **`/pause` command handler**:
   - Call `writePauseFlag(repoPath)` (from ticket 0104).
   - Respond with a confirmation message, e.g. `"Orchestrator paused. In-flight agents will finish but no new work will start."`
   - If already paused, still succeed (idempotent) but note it: `"Orchestrator is already paused."`

3. **`/resume` command handler**:
   - Call `removePauseFlag(repoPath)`.
   - Respond with a confirmation message, e.g. `"Orchestrator resumed. New work will be picked up on the next tick."`
   - If not currently paused, still succeed but note it: `"Orchestrator was not paused."`

4. Both handlers should check `isPaused(repoPath)` before acting to provide accurate feedback.

### Notes

- These commands modify local filesystem state only (`.scriptorium/pause` file).
- The orchestrator reads this flag independently on each tick (ticket 0104).
- Use the pause flag procs from the module created in ticket 0104.
