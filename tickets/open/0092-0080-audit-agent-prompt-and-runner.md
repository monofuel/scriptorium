# 0080-audit-agent-prompt-and-runner

**Area:** audit-agent

**Depends:** 0078

## Description

Create the audit agent module (`src/scriptorium/audit_agent.nim`) with the prompt builder and runner proc that invokes the agent harness.

### Requirements

- Create `src/scriptorium/audit_agent.nim`.
- Implement `buildAuditPrompt*(specContent: string, agentsMdContent: string, diffContent: string): string` that constructs a prompt instructing the agent to:
  1. Check spec compliance: compare `spec.md` content against the codebase, report divergences (features spec describes that code doesn't implement, code behaviors not in spec, contradictions).
  2. Check AGENTS.md compliance: review the cumulative diff for violations of project conventions.
  3. Output a markdown report with sections "## Spec Drift" and "## AGENTS.md Violations", each item citing the relevant rule and offending code location.
- Implement `runAuditAgent*(repoPath: string, runner: AgentRunner = runAgent): string` that:
  1. Loads config via `loadConfig`.
  2. Opens a plan worktree to read `spec.md` and `AGENTS.md` from the repo root.
  3. Computes the cumulative diff since the last audited commit using `git diff <last-audited-commit>..HEAD`.
  4. Builds the prompt and runs the agent using `AgentRunRequest` with the audit config (model, harness, reasoningEffort from `cfg.agents.audit`).
  5. Uses `resolveModel` on the audit model.
  6. Sets `skipGitRepoCheck: true` since it runs in a worktree.
  7. Sets reasonable timeouts (e.g., `noOutputTimeoutMs: 120_000`, `hardTimeoutMs: 300_000`).
  8. Returns the agent's output (the markdown report).
- The audit agent must be **read-only** — it must not modify any files. Use `enforceNoWrites` from `architect_agent.nim` to verify the worktree is clean after the agent runs.
- Add the module to the import list in `src/scriptorium/orchestrator.nim`.

### Context

Follow the pattern of `runReviewAgent` in `src/scriptorium/merge_queue.nim` and `runArchitectAreas` in `src/scriptorium/architect_agent.nim` for how to construct `AgentRunRequest` and invoke the runner. Use `loadSpecFromPlanPath` from `architect_agent.nim` to read the spec. Use `runCommandCapture` from `git_ops.nim` for the git diff.
