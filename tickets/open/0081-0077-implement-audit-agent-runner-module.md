<!-- file: tickets/open/0077-audit-agent-module.md -->
# 0077 — Implement audit agent runner module

**Area:** audit-agent
**Depends:** 0074, 0075, 0076

Implement the core audit agent module that executes an audit and writes the report.

## Details

Create `src/scriptorium/audit_agent.nim`:

1. Add a `runAudit(repoPath: string): string` proc that:
   - Loads the audit config from `loadConfig()`.
   - Computes the cumulative diff: `git diff <lastAuditedCommit>..HEAD` on the default branch.
   - Reads `spec.md` from the plan branch (`git show scriptorium/plan:spec.md`).
   - Reads `AGENTS.md` from the repo root.
   - Builds the prompt using `buildAuditAgentPrompt`.
   - Calls `runAgent` with an `AgentRunRequest` configured for:
     - Model from `agents.audit` config (default Haiku).
     - Log root: `.scriptorium/logs/audit/`.
     - Short timeouts (e.g., 5 min hard timeout, 2 min no-output timeout — audit should be fast).
     - No MCP endpoint (read-only, no tools needed).
     - Working dir: `repoPath` (reads from repo, no worktree needed).
   - Writes the agent output as a markdown report to `.scriptorium/logs/audit/audit_{timestamp}.md`.
   - Updates the audit state via `saveAuditState` with the current HEAD.
   - Returns the report file path.

2. The report filename should use the timestamp format consistent with existing logs: `yyyy-MM-dd'T'HH-mm-ss'Z'`.

3. Create the `.scriptorium/logs/audit/` directory if it doesn't exist (use `createDir`).

Follow the patterns in `architect_agent.nim` and `manager_agent.nim` for agent execution.

## Verification

- `make test` passes.
- Code compiles and follows existing agent patterns.
