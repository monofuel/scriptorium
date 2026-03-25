# 0108 — Implement chat message to architect invocation

**Area:** discord
**Depends:** 0105

## Description

Implement the core chat message handler that sends non-slash Discord messages to the architect and posts the response back to the channel.

### Requirements

1. **In the message handler** in `src/scriptorium/discord_bot.nim`, when a non-slash message arrives from an allowed user in the configured channel:
   - Invoke the architect using the same pattern as `updateSpecFromArchitect` in `architect_agent.nim`:
     a. Acquire the plan worktree lock via `withLockedPlanWorktree(repoPath, ...)`.
     b. Load the existing spec from the plan worktree.
     c. Build the architect prompt using `buildArchitectPlanPrompt(repoPath, planPath, messageText, existingSpec)` from `prompt_builders.nim`.
     d. Run the architect via `runPlanArchitectRequest(...)` with the architect agent config.
     e. Enforce write allowlist to `spec.md` only via `enforceWriteAllowlist`.
     f. If spec changed, commit with `git add` + `git commit`.
   - Extract the architect's response from `agentResult.lastMessage` (falling back to `agentResult.stdout`).
   - Post the response back to the Discord channel.

2. **Each message is stateless** — no Discord chat history is carried between messages. Each invocation is independent.

3. **Response handling**:
   - Discord messages have a 2000-character limit. If the architect response exceeds this, truncate with a `"... [truncated]"` marker.
   - If the spec was modified, append a note: `"[spec.md updated]"` to the response.

4. **Error handling**: If the architect invocation fails (e.g., lock contention, timeout), post a brief error message to the channel rather than crashing the bot. The bot process should remain running.

### Notes

- Follow the same invocation pattern as `interactive_sessions.nim` lines 97-138 (the plan session turn logic), but without maintaining turn history.
- Load config via `loadConfig(repoPath)` to get `agents.architect` settings.
- The transactional commit lock (`withLockedPlanWorktree`) ensures safe concurrent access with the orchestrator.
- Use `runAgent` as the default `AgentRunner` (same as `updateSpecFromArchitect`).
- Import from: `architect_agent`, `config`, `lock_management`, `prompt_builders`, `shared_state`, `agent_runner`.
