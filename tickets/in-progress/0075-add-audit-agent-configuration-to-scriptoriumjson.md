<!-- file: 0074-audit-agent-config.md -->
# Add audit agent configuration to scriptorium.json

**Area:** audit-agent

## Description

Add an `audit` field to the `AgentConfigs` object in `src/scriptorium/config.nim` and wire it through configuration loading.

## Tasks

1. In `src/scriptorium/config.nim`:
   - Add `const DefaultAuditModel = "claude-haiku-4-5-20251001"` to the constants block.
   - Add `audit*: AgentConfig` field to the `AgentConfigs` object.
   - In `defaultConfig()`, set `audit: defaultAgentConfig(DefaultAuditModel)`.
   - In `loadConfig()`, add `mergeAgentConfig(result.agents.audit, parsed.agents.audit)` alongside the existing agent config merges.

2. Verify `scriptorium.json` is **not** modified — the audit config uses defaults unless explicitly overridden. The existing JSON (which lacks an `audit` key) should still parse correctly via jsony (missing fields get zero-values, which `mergeAgentConfig` skips).

3. Add a unit test in `tests/test_config.nim` (or the existing config test file) confirming:
   - Default audit model is `claude-haiku-4-5-20251001`.
   - Default audit harness is `claude-code`.
   - A JSON blob with `"agents": {"audit": {"model": "claude-sonnet-4-6"}}` overrides the audit model correctly.

## References

- `src/scriptorium/config.nim` — existing config types and loading.
- Spec section 19: `agents.audit` in `scriptorium.json`, supporting `harness`, `model`, and `reasoningEffort`. Default model is `claude-haiku-4-5-20251001`.
````

````markdown
<!-- file: 0075-audit-agent-prompt-template.md -->
# Create audit agent prompt template

**Area:** audit-agent

## Description

Create the prompt template that the audit agent will use. The prompt instructs the agent to check spec compliance and AGENTS.md compliance, producing a structured markdown report.

## Tasks

1. Create `src/scriptorium/prompts/audit_agent.md` with a prompt template containing these placeholders:
   - `{{spec}}` — contents of `spec.md`
   - `{{agents_md}}` — contents of `AGENTS.md`
   - `{{diff}}` — cumulative git diff since last audit
   - `{{last_audit_commit}}` — the commit hash of the last audit (or "initial audit" if first run)

2. The prompt should instruct the agent to:
   - Compare `spec.md` against the codebase (represented by the diff and general knowledge). Report divergences: features spec describes that code doesn't implement, code behaviors not in spec, contradictions.
   - Compare `AGENTS.md` conventions against the diff. Report violations citing the rule and offending code location.
   - Output a markdown report with two sections: "## Spec Drift" and "## AGENTS.md Violations". Each item should cite the relevant rule/section and the file:line of the offending code.
   - If no issues are found in a section, write "No issues found."

3. Register the template in `src/scriptorium/prompt_catalog.nim`:
   - Add `AuditAgentTemplate* = staticRead(PromptDirectory & "audit_agent.md")`.

## References

- `src/scriptorium/prompts/` — existing prompt templates for pattern reference.
- `src/scriptorium/prompt_catalog.nim` — template registration.
- Spec section 19: output format and audit scope.
````

````markdown
<!-- file: 0076-last-audited-commit-tracking.md -->
# Track last audited commit hash on plan branch

**Area:** audit-agent

## Description

The orchestrator needs to track which commit was last audited so it can compute the cumulative diff. Store this as a simple file on the `scriptorium/plan` branch.

## Tasks

1. In a new file `src/scriptorium/audit_agent.nim`, add constants and helper procs:
   - `const AuditLastCommitPath* = "audit/.last-commit"` — path within the plan branch worktree.
   - `const AuditLogDir = "audit"` — log directory name under `.scriptorium/logs/`.
   - `const AuditCommitMessage = "scriptorium: update last audited commit"`.
   - `proc readLastAuditedCommit*(planPath: string): string` — reads `audit/.last-commit` from the plan worktree. Returns empty string if file doesn't exist.
   - `proc writeLastAuditedCommit*(planPath: string, commitHash: string)` — writes the commit hash to `audit/.last-commit`, creates the `audit/` directory if needed, stages and commits on the plan branch.

2. Add `proc auditCumulativeDiff*(repoPath: string, lastCommit: string): string` — runs `git diff <lastCommit>..HEAD` on the default branch and returns the diff text. If `lastCommit` is empty, returns the diff of the last 5 commits (to keep the first audit bounded).

3. Add a unit test verifying `readLastAuditedCommit` returns empty string when the file doesn't exist, and returns the stored hash after `writeLastAuditedCommit`.

## References

- `src/scriptorium/git_ops.nim` — `runCommandCapture`, `gitRun`, `withPlanWorktree` for plan branch operations.
- `src/scriptorium/shared_state.nim` — `PlanSpecPath` and other plan branch path constants.
- Spec section 19: orchestrator tracks "last audited commit" hash.
````

````markdown
<!-- file: 0077-audit-agent-runner.md -->
# Implement audit agent runner proc

**Area:** audit-agent

**Depends:** 0074, 0075, 0076

## Description

Implement the core proc that assembles the audit prompt, runs the agent, and writes the report to `.scriptorium/logs/audit/`.

## Tasks

1. In `src/scriptorium/audit_agent.nim`, add:
   - `proc runAuditAgent*(repoPath: string, runner: AgentRunner = runAgent): bool` that:
     a. Loads config via `loadConfig(repoPath)`.
     b. Reads the current default branch HEAD commit via `defaultBranchHeadCommit(repoPath)`.
     c. Reads the last audited commit via `readLastAuditedCommit` from the plan branch.
     d. If HEAD == last audited commit, log "audit: nothing changed since last audit" and return false.
     e. Computes the cumulative diff via `auditCumulativeDiff`.
     f. Reads `spec.md` from the plan branch and `AGENTS.md` from the repo root.
     g. Renders the `AuditAgentTemplate` with bindings for `spec`, `agents_md`, `diff`, and `last_audit_commit`.
     h. Runs the agent via `runner` with:
        - `harness`: `cfg.agents.audit.harness`
        - `model`: `resolveModel(cfg.agents.audit.model)`
        - `workingDir`: `repoPath`
        - `logRoot`: `repoPath / ".scriptorium" / "logs" / "audit"`
        - `ticketId`: `"audit"` (for log naming)
        - Reasonable timeouts (e.g., `noOutputTimeoutMs: 120_000`, `hardTimeoutMs: 300_000`).
     i. Writes the agent's `lastMessage` (the report) to `.scriptorium/logs/audit/audit_<timestamp>.md`.
     j. Updates the last audited commit to the current HEAD on the plan branch.
     k. Logs summary and returns true.

2. Use `createDir` to ensure `.scriptorium/logs/audit/` exists before writing.

3. Use the `renderPromptTemplate` proc from `prompt_catalog.nim` for template rendering, and `formatFileTimestamp`-style naming for the report file (follow the pattern in `logging.nim`).

## References

- `src/scriptorium/agent_runner.nim` — `AgentRunRequest`, `runAgent`.
- `src/scriptorium/config.nim` — `loadConfig`, `resolveModel`.
- `src/scriptorium/prompt_catalog.nim` — `renderPromptTemplate`, `AuditAgentTemplate`.
- `src/scriptorium/architect_agent.nim` — pattern for how other agents assemble prompts and run.
- Spec section 19: audit output and scope.
````

````markdown
<!-- file: 0078-audit-cli-command.md -->
# Add `scriptorium audit` CLI command

**Area:** audit-agent

**Depends:** 0077

## Description

Add the `audit` subcommand to the CLI so users can run the audit agent on demand.

## Tasks

1. In `src/scriptorium.nim`:
   - Add `"audit"` to the Usage string (it's already listed in the spec but not yet in the CLI help).
   - Import `audit_agent` from the orchestrator module (it should be exported by `orchestrator.nim` — add the export if needed).
   - Add a `cmdAudit()` proc that calls `runAuditAgent(getCurrentDir())` and prints whether issues were found.
   - Add a `"audit"` case to the command dispatch block.

2. In `src/scriptorium/orchestrator.nim`:
   - Add `audit_agent` to the import list.
   - Add `audit_agent` to the export list.

3. Verify `nim r src/scriptorium.nim audit` runs successfully (it should report "nothing changed" if no commits since last audit, or produce a report).

## References

- `src/scriptorium.nim` — CLI dispatch, lines 1-80.
- `src/scriptorium/orchestrator.nim` — module imports/exports.
- Spec section 19: `scriptorium audit` CLI command runs the audit agent on demand.
````

````markdown
<!-- file: 0079-audit-merge-queue-trigger.md -->
# Trigger audit agent when merge queue drains

**Area:** audit-agent

**Depends:** 0077

## Description

Wire the audit agent into the orchestrator main loop so it runs automatically when the merge queue drains after processing one or more items.

## Tasks

1. In `src/scriptorium/orchestrator.nim`, add state tracking:
   - `var mergeQueueProcessedSinceLastAudit = false` — set to true whenever `processMergeQueue` returns true.
   - After step 7 (merge queue processing), detect when the queue is empty and `mergeQueueProcessedSinceLastAudit` is true. This is the "drain" condition.

2. When the drain condition is met:
   - Check if an audit agent slot is available (the audit uses one shared pool slot).
   - Call `runAuditAgent(repoPath, runner)` (or start it async if using the agent pool — but since audit is lightweight and runs in the background, a synchronous call after merge queue drain is acceptable for the initial implementation).
   - Reset `mergeQueueProcessedSinceLastAudit` to false.
   - Log "audit: triggered by merge queue drain".

3. Secondary trigger: after `runArchitectAreas` returns `architectChanged = true`, also set a flag `specChangedSinceLastAudit = true`. When the merge queue next drains (or immediately if queue is empty), trigger the audit.

4. The audit agent must NOT block the merge queue or delay other agents. If a slot is not available, skip the audit for this tick (it will be triggered on the next drain or idle).

## References

- `src/scriptorium/orchestrator.nim:134-338` — main loop with merge queue processing at step 7.
- `src/scriptorium/merge_queue.nim` — `processMergeQueue` return value.
- Spec section 19: trigger on merge queue drain and spec changes.
````

````markdown
<!-- file: 0080-audit-agent-tests.md -->
# Add unit tests for audit agent

**Area:** audit-agent

**Depends:** 0076, 0077

## Description

Add unit tests covering the audit agent's core logic: commit tracking, diff computation, prompt rendering, and report writing.

## Tasks

1. Create `tests/test_audit_agent.nim` with tests:
   - **Last commit tracking**: Initialize a test git repo, verify `readLastAuditedCommit` returns "" initially, write a commit hash, verify it reads back correctly.
   - **Cumulative diff**: Create a test repo with multiple commits, verify `auditCumulativeDiff` returns the expected diff between two commits. Also test the empty-last-commit case (should return bounded diff).
   - **Prompt rendering**: Verify the audit prompt template renders without errors when given all required bindings (`spec`, `agents_md`, `diff`, `last_audit_commit`). Verify it raises on missing bindings.
   - **Report output path**: Verify the report file is written to `.scriptorium/logs/audit/` with the expected naming pattern.

2. Follow the existing test patterns in `tests/test_*.nim`. Use `tests/config.nims` for path setup.

3. Ensure tests compile and pass with `nim r tests/test_audit_agent.nim`.

## References

- `tests/test_*.nim` — existing test patterns.
- `tests/config.nims` — test path configuration.
- AGENTS.md: unit tests use mocks/fakes, no real external services.
````

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0075-add-audit-agent-configuration-to-scriptoriumjson
