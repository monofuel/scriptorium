# Spec

## Product Summary

`scriptorium` is a git-native agent orchestration tool for software projects.

- Planning state lives on a dedicated `scriptorium/plan` branch.
- Runtime workflow is Architect -> Manager -> Coding agent -> Review agent -> merge queue.
- Orchestration is local-first and uses deterministic managed git worktrees plus an MCP HTTP server for completion signaling.

## 1. CLI Surface And Initialization

- The CLI must support: `--init`, `run`, `status`, `plan`, `ask`, `audit`, `worktrees`, `--version`, `--help`.
- `scriptorium --init [path]` must:
  - fail if target is not a git repository,
  - fail if `scriptorium/plan` already exists,
  - create orphan branch `scriptorium/plan`,
  - create planning structure:
    - `areas/`
    - `tickets/open/`
    - `tickets/in-progress/`
    - `tickets/done/`
    - `decisions/`
    - `spec.md` placeholder,
  - write `.gitkeep` files in initialized directories,
  - create an initial commit on the plan branch.
- The initialized `spec.md` placeholder must be:
  - `# Spec`
  - blank line
  - `Run \`scriptorium plan\` to build your spec with the Architect.`

## 2. Planning And Ask Sessions

- Planning runs against a managed plan worktree checked out from `scriptorium/plan`.
- The managed plan worktree path must be deterministic under `/tmp/scriptorium/.../worktrees/plan`.
- Both one-shot (`scriptorium plan <prompt>`) and interactive (`scriptorium plan`) planning must:
  - run the Architect with working directory set to the managed plan worktree,
  - include repo-root path context so the Architect can read source files from the main project,
  - skip git repo checks inside the agent harness for plan worktrees,
  - enforce a post-run write allowlist of `spec.md` only,
  - use the transactional commit lock (§17) so concurrent planner or manager writes fail fast.
- One-shot planning must:
  - require a non-blank prompt,
  - commit only when `spec.md` changes,
  - use commit message `scriptorium: update spec from architect`.
- Interactive planning must support:
  - `/show` to print current `spec.md`,
  - `/help` to list commands,
  - `/quit` and `/exit` to leave the session,
  - unknown slash commands without invoking the Architect,
  - in-memory turn history for the current session,
  - streamed Architect status output during a turn,
  - Ctrl+C and EOF exit handling.
- Interactive planning commits must:
  - create at most one commit per turn that changes `spec.md`,
  - use commit message `scriptorium: plan session turn <n>`.
- `scriptorium ask` must provide a read-only interactive Architect Q&A session that:
  - uses the same managed plan worktree and repo-root context,
  - includes current `spec.md` and in-memory conversation history in prompts,
  - supports `/show`, `/help`, `/quit`, and `/exit`,
  - streams Architect status output during a turn,
  - rejects any file writes in the plan worktree,
  - makes no plan-branch commits.

## 3. Orchestrator Run Loop

- `scriptorium run` must start:
  - the orchestrator singleton PID guard (see §17),
  - the orchestrator polling loop,
  - the local MCP HTTP server used by coding agents,
  - repository-backed logging with configurable log level.
- Endpoint source is `scriptorium.json` `endpoints.local`, defaulting to `http://127.0.0.1:8097`.
- Polling is continuous with idle sleep between ticks.
- Work must be gated by:
  - existence of `scriptorium/plan` branch,
  - healthy `master`,
  - runnable `spec.md` (not blank and not the init placeholder).
- `master` health means required quality targets pass in order on a `master` worktree:
  - `make test`
  - `make integration-test`
- Health check results are cached on the plan branch in `health/cache.json` so they survive container restarts and session boundaries. Cache entries are keyed by commit hash. On startup, cached results skip redundant health checks.
- If spec is not runnable, orchestrator must log: `WAITING: no spec — run 'scriptorium plan'`.
- Tick order:
  1. Poll completed agents (managers + coders) via `checkCompletedAgents()`.
     - For completed managers: acquire commit lock, write tickets, commit, release. Log results.
     - For completed coders: handle as before (move ticket, queue merge, etc).
  2. Check health.
  3. Run architect (sequential, if spec changed). Must complete before managers are spawned.
  4. Read areas needing tickets (brief commit lock).
  5. For each area needing tickets, if slots available, start a manager agent (at most 1 new agent per tick — see staggered start rule).
  6. For each assignable ticket, if slots available, start a coding agent (at most 1 new agent per tick — see staggered start rule).
  7. Process at most one merge-queue item.
  8. Sleep.
- Managers are prioritized over coders when slots are scarce, since manager completions unblock future coding work.
- The orchestrator must cache `master` health by `master` HEAD commit and recompute only when `master` changes.

## 4. Planning Artifacts And State Model

- Plan branch file layout is authoritative:
  - `spec.md`
  - `areas/*.md`
  - `tickets/open/*.md`
  - `tickets/in-progress/*.md`
  - `tickets/done/*.md`
  - `queue/merge/pending/*.md`
  - `queue/merge/active.md`
  - `health/cache.json`
- `queue/merge/` may be created lazily by orchestrator queue initialization rather than by `--init`.
- Tickets must exist in exactly one state directory at a time.
- Ticket state transitions must be represented by single orchestrator transition commits.
- Ticket IDs in filenames must be monotonic and zero-padded.
- Merge queue item IDs in filenames must also be monotonic and zero-padded.
- Areas are persistent ownership zones that evolve with the spec, not one-shot artifacts; the architect updates or creates area files whenever `spec.md` changes, and the manager re-tickets areas whose content has changed.
- Area IDs are derived from area markdown filenames.
- Area-to-ticket linkage is carried in ticket markdown via `**Area:** <area-id>`.
- Ticket assignment must:
  - move the oldest open ticket to `tickets/in-progress/`,
  - create or reuse deterministic ticket branch name `scriptorium/ticket-<id>`,
  - create a deterministic managed code worktree path under `/tmp/scriptorium/.../worktrees/tickets/`,
  - record worktree metadata in ticket markdown via `**Worktree:** <absolute-path>`.
- Active merge queue metadata must store: ticket path, ticket id, branch, worktree, summary.

## 5. Architect And Area Generation

- Area generation is agent-driven: the Architect writes area files directly under `areas/`.
- Area generation is continuous and content-hash driven:
  - `spec.md` must be runnable,
  - the orchestrator stores a SHA-1 hash of `spec.md` in `areas/.spec-hash`,
  - on first run (no `.spec-hash` marker), the architect generates areas and writes the marker,
  - on subsequent ticks, the architect re-runs only when the current `spec.md` hash differs from the stored hash,
  - after area generation, the orchestrator updates `areas/.spec-hash` and commits the marker separately,
  - if areas already exist but no `.spec-hash` marker is present (migration), the orchestrator writes the marker from the current spec without re-running the architect.

## 6. Manager And Ticket Generation

- Manager execution is per-area and concurrent: each eligible area is handled by an independent manager agent invocation using `manager_tickets.md`.
- Manager ticket generation is continuous and content-hash driven:
  - the orchestrator stores per-area SHA-1 hashes in `tickets/.area-hashes` (tab/colon-separated `area-id:hash`, one per line, sorted),
  - areas with open or in-progress tickets are always suppressed (blocks concurrent work on the same area),
  - when `tickets/.area-hashes` exists, areas whose content hash differs from the stored hash are eligible for re-ticketing, even if previous tickets for that area are done,
  - when `tickets/.area-hashes` does not exist (legacy fallback), areas with any ticket in any state are suppressed,
  - after ticket generation, the orchestrator computes and writes hashes for all current areas and commits the hash file separately.
- Manager agents generate ticket content in memory — they do not write to the plan worktree. Only the orchestrator main thread writes to the plan worktree.
- Manager writes are constrained by a write-prefix allowlist to `tickets/open/`.
- Manager execution must preserve the dirty state of the main repository outside the plan worktree.
- Manager-generated ticket filenames must be assigned by the orchestrator, not by the agent prompt output.
- Per-area manager flow:
  1. Orchestrator briefly acquires the commit lock to snapshot area content for all areas needing tickets, then releases the lock.
  2. For each area, if a slot is available in the shared pool, spawn a manager agent thread.
  3. The manager thread generates ticket documents in memory and sends results back through the shared agent result channel.
  4. On the next tick, `checkCompletedAgents()` picks up manager completions.
  5. The orchestrator main thread acquires the commit lock, calls `writeTicketsForArea()` to persist tickets for one completed manager, commits, and releases the lock. Each completed manager's write is a separate short lock acquisition.

## 7. Coding Agent Execution

- Coding-agent execution must:
  - run in the assigned ticket worktree,
  - receive the ticket path, ticket content, repo path, and worktree path in its prompt,
  - append structured agent run notes to the ticket markdown,
  - persist backend, exit code, attempt, attempt count, timeout, log file, last-message file, last message tail, and stdout tail in those notes,
  - enqueue merge request metadata only when the coding agent calls the MCP `submit_pr` tool.
- Merge-queue enqueueing must use MCP tool state, not stdout scanning.
- Stall detection: a "stall" is a coding agent turn that completes without calling `submit_pr`. On stall:
  - Run `make test` in the agent's worktree and capture the result.
  - If tests fail, the continuation prompt includes test failure output and a directive to fix tests.
  - If tests pass, the continuation prompt includes a note that tests pass and a directive to continue.
  - Retry with a continuation prompt including the original ticket content.
  - Retries use the bounded retry mechanism (maxAttempts in AgentRunRequest).
  - Each retry is logged with attempt number and ticket ID.
- Log forwarding: during coding agent execution, the orchestrator forwards meaningful stream events (tool calls, file activity, status changes) to orchestrator logs in real time, prefixed with ticket ID.

## 8. Pre-Submit Test Gate

- The `submit_pr` MCP tool must run `make test` in the agent's worktree before accepting a submission.
- If tests fail: return an error response to the agent with test failure output, directing the agent to fix tests and call `submit_pr` again. The merge request is NOT enqueued.
- If tests pass: record the submit summary and return success. The merge request is enqueued.
- The agent remains running during the test execution — `submit_pr` blocks until tests complete.

## 9. Review Agent

- After a coding agent successfully submits via `submit_pr`, the orchestrator runs a review agent before merge queue processing.
- The review agent is configured under `agents.reviewer` in `scriptorium.json`, supporting `harness`, `model`, and `reasoningEffort`.

### Review Flow

- When processing a pending merge queue item, before quality gates and merging:
  1. Start a review agent session in the ticket's worktree.
  2. The review agent prompt includes:
     - The full ticket content (intent and requirements).
     - The diff of changes against `master`.
     - The relevant area content.
     - The submit summary from the coding agent.
     - The project's `AGENTS.md` content (conventions, naming, error handling, file organization).
     - Relevant `spec.md` sections (at minimum the section related to the ticket's area).
  3. The review agent has access to a `submit_review` MCP tool with three actions:
     - `approve`: accepts the changes, merge proceeds.
     - `approve_with_warnings`: accepts with logged warnings for minor style issues.
     - `request_changes`: rejects the changes with a `feedback` string explaining what needs to change.

### Review Enforcement

- The review agent must enforce `AGENTS.md` conventions: check the diff against project naming, logging, error handling, and file organization rules. Flag violations.
- The review agent must enforce `spec.md` compliance: check that the implementation matches the spec and flag contradictions.
- The review agent must flag code quality issues in the diff:
  - Unreachable code or unused imports introduced by the PR.
  - Leftover artifacts from abandoned approaches (commented-out code, TODO comments referencing completed work, variables assigned but never read).
  - Changes unrelated to the ticket's stated goal (without being overly aggressive about legitimate incidental fixes).
- Graduated severity:
  - Minor style issues and small convention deviations: approve with warnings logged in review notes.
  - Substantive violations (wrong behavior, spec contradictions, convention violations affecting correctness, dead code, unrelated changes): request changes.

### Review Outcomes

- **Approved:** Merge queue proceeds with quality gate flow (merge master, run tests, fast-forward merge).
- **Changes requested:** Pending queue item is removed. Ticket stays in-progress. Review feedback is appended to ticket markdown. A new coding agent session starts with original ticket content plus review feedback, using the same worktree/branch. Review-driven retries count toward total attempt count.
- **Stall (review agent exits without calling `submit_review`):** Treat as approval. Log a warning.

### Review Lifecycle Logging

- Review start, approved, approved-with-warnings, changes requested, and stall events are all logged at INFO level with ticket ID.
- Review outcomes are appended to ticket markdown as structured review notes.
- Review reasoning (not just the decision) must be logged so violations are traceable in the review logs.

## 10. Merge Queue Safety Contract

- Merge queue is single-flight; each processing pass handles at most one pending item.
- Queue processing must:
  - ensure queue metadata exists,
  - set `queue/merge/active.md` to the currently processed pending item,
  - merge `master` into the ticket branch worktree,
  - run required quality targets (`make test`, `make integration-test`) in the ticket worktree,
  - on success, fast-forward merge the ticket branch into `master`,
  - on success, append a merge success note and move ticket `in-progress -> done`,
  - on failure, append a merge failure note and move ticket `in-progress -> open`.
- Queue metadata must be cleaned up after success, failure, or terminal stale-item cleanup.
- If a pending queue item references a ticket already moved to `open` or `done`, queue processing must remove the stale queue item and clear active metadata.
- Merge queue success and failure notes must include the submit summary and relevant output tails.
- Stale managed worktrees for non-active tickets must be removable by cleanup.
- Pending merge queue items are processed in submission order (FIFO by queue item ID).

## 11. Parallel Ticket Assignment And Concurrency

- The orchestrator assigns multiple open tickets concurrently when they touch independent areas.
- Independence is determined by area: two tickets are independent if they reference different areas.
- Tickets that reference the same area must be serialized — only one ticket per area may be in-progress at a time.
- Assignment order is oldest-first: scan open tickets in ID order, assign each whose area is not already occupied.
- Each assigned ticket gets its own worktree and branch.
- Managers and coding agents share a single `maxAgents` slot pool, tracked in a shared `agent_pool` module.
- An `AgentRole` enum (`arCoder`, `arManager`) tags each agent slot so the orchestrator can distinguish completions.
- `AgentSlot` gains a `role` field. Manager slots use `areaId` as their identifier and have no branch or worktree. Coder slots retain `ticketId`, `branch`, and `worktree` fields.
- `startAgentAsync()` accepts a role and a generic worker proc.
- `checkCompletedAgents()` returns completions tagged with role.
- Concurrency limit is configurable via `scriptorium.json` under `concurrency.maxAgents` (integer, default 4). A value of 1 restores serial behavior.
- Staggered start rule: the orchestrator starts at most 1 new coding agent per tick to avoid burst-spawning. Managers are exempt from this limit (they are lightweight and produce no API load comparable to coders). If multiple open tickets are assignable, one is started this tick and the rest wait for subsequent ticks.
- The orchestrator logs when an agent slot opens or fills.

## 12. Resource Management

- Track aggregate `stdout_bytes` across all running agents as a proxy for token consumption.
- If `concurrency.tokenBudgetMB` is set in `scriptorium.json`, pause new ticket assignment when cumulative session `stdout_bytes` exceeds the budget. Allow running agents to complete normally.
- The orchestrator does not perform its own rate limit detection or backpressure. The coding harness (Claude Code, Codex) handles HTTP 429 retries internally.

## 13. Harness Routing And Agent Backends

- Runtime agent configuration is role-based and stored under `scriptorium.json` `agents`:
  - `agents.architect`
  - `agents.coding`
  - `agents.manager`
  - `agents.reviewer`
  - `agents.audit`
- Each role config supports: `harness`, `model`, `reasoningEffort`.
- Model-prefix harness inference:
  - `claude-*` -> `claude-code`
  - `codex-*` and `gpt-*` -> `codex`
  - all other models -> `typoi`
- The role config may explicitly set `harness` instead of relying on model-prefix inference.
- Current backend implementation state:
  - `codex` implemented,
  - `claude-code` implemented,
  - `typoi` routed but fails fast as unimplemented.
- Current code defaults are test-focused:
  - architect, coding, and manager default to model `codex-fake-unit-test-model`
  - default harness is `codex`
  - default reasoning-effort values are empty.
- Codex harness must provide:
  - deterministic command shape around `codex exec --json ... --output-last-message ...`,
  - `--dangerously-bypass-approvals-and-sandbox`,
  - optional `--skip-git-repo-check`,
  - MCP server injection through codex `-c` config args,
  - JSONL-style run logs,
  - parsed stream events for heartbeat, reasoning, tool, status, and message output,
  - last-message capture,
  - no-output and hard-timeout handling,
  - bounded retry support with a continuation prompt,
  - reasoning-effort normalization for supported codex models.
- Claude Code harness must provide:
  - deterministic non-interactive command shape around `claude --print --output-format stream-json --verbose`,
  - `--dangerously-skip-permissions`,
  - optional MCP injection through `--mcp-config`,
  - stream-json event parsing into heartbeat, reasoning, tool, status, and message output,
  - last-message extraction,
  - no-output and hard-timeout handling,
  - bounded retry support with a continuation prompt,
  - reasoning-effort normalization for supported Claude Code values.

## 14. Observability And Metrics

### Tick Summary

- At the end of each tick, log a single INFO-level summary line with: architect status, manager status, coding ticket ID + status + wall time, merge status, and open/in-progress/done ticket counts.

### Ticket Lifecycle Logging

- Log an INFO-level line for every ticket state transition with timing: assignment, coding agent start/finish, PR submission, merge queue entry, merge start/success/failure, completion, reopen, stall detection, pre-retry test, and continuation.

### Per-Ticket Metrics

- Capture structured metrics per ticket in agent run notes: `wall_time_seconds`, `coding_wall_seconds`, `test_wall_seconds`, `attempt_count`, `outcome`, `failure_reason`, `model`, `stdout_bytes`.

### Ticket Difficulty Prediction

- Before ticket assignment, run a prediction prompt estimating difficulty (`trivial`/`easy`/`medium`/`hard`/`complex`), expected duration, and reasoning. Log and persist in ticket markdown.

### Ticket Post-Analysis

- After a ticket reaches done/reopened/parked, compare predicted vs actual metrics. Persist assessment in ticket markdown.

### Session Summary

- On shutdown, log aggregate counts (uptime, ticks, tickets completed/reopened/parked, merge queue processed) and averages (ticket wall, coding wall, test wall, first-attempt success rate).

## 15. Status And Worktree Visibility

- `scriptorium status` must report:
  - open, in-progress, and done ticket counts,
  - active ticket id/path/branch/worktree,
  - elapsed time for the current in-progress ticket,
  - last N completed tickets (default 5) with outcome and wall time,
  - cumulative first-attempt success rate.
- If there is no active ticket, `status` must print `Active Agent: none`.
- Active ticket resolution must prefer the active merge-queue item when present, then fall back to the first in-progress ticket worktree.
- `scriptorium worktrees` must list active in-progress ticket worktrees with worktree path, ticket id, and branch mapping.
- If no in-progress ticket worktrees exist, `scriptorium worktrees` must print: `scriptorium: no active ticket worktrees`.
- Managed repository state lives in deterministic per-repo paths under `/tmp/scriptorium/`.

## 16. Config, Logging, And CI

- Runtime config file is `scriptorium.json`.
- Config supports:
  - `agents.architect.{harness, model, reasoningEffort}`
  - `agents.coding.{harness, model, reasoningEffort}`
  - `agents.manager.{harness, model, reasoningEffort}`
  - `agents.reviewer.{harness, model, reasoningEffort}`
  - `agents.audit.{harness, model, reasoningEffort}`
  - `endpoints.local`
  - `logLevel`
  - `concurrency.maxAgents` (integer, default 4)
  - `concurrency.tokenBudgetMB` (integer, optional)
- `SCRIPTORIUM_LOG_LEVEL` must override config-file `logLevel` when present.
- Repository test commands:
  - `make test` runs `tests/test_*.nim`
  - `make integration-test` runs `tests/integration_*.nim`
  - `make e2e-test` runs end-to-end coverage
- CI baseline:
  - build workflow runs unit tests on push and PR,
  - build workflow builds the linux binary on push,
  - integration workflow runs on `master` push and `workflow_dispatch`,
  - e2e workflow runs on `master` push and `workflow_dispatch`.

## 17. Plan Branch Locking

Two mechanisms protect plan branch state:

### Orchestrator Singleton PID Guard

- On `scriptorium run` startup, write `.scriptorium/orchestrator.pid` containing the process PID and a startup timestamp.
- If the file already exists, read the PID and check liveness with `kill(pid, 0)`:
  - If the PID is alive: abort with a clear error message.
  - If the PID is dead: log a warning, overwrite the PID file, proceed.
- On clean shutdown, delete the PID file.
- This is a one-time startup check, not an acquired/released lock. It is not checked during operation.
- The PID check does not work across container boundaries (different PID namespaces). The constraint is that scriptorium runs either always in a container or always on the host for a given repo, never both simultaneously.

### Transactional Commit Lock

A short-lived file lock held only for the duration of a read-modify-commit cycle on the plan branch.

- **Contract:**
  - Acquired immediately before a plan branch write operation.
  - The lock holder reads state, modifies files, runs `git commit`, then releases.
  - Never held during agent execution, API calls, test runs, or anything beyond a few seconds.
  - Maximum expected hold time: < 2 seconds (a `git add` + `git commit`).
- **Implementation:**
  - Lock file: `.scriptorium/commit.lock` (a regular file, not a directory).
  - On acquisition, write a JSON object: `{"pid": <pid>, "timestamp": <unix_epoch>}`.
  - On release, delete the file.
  - Staleness threshold: 30 seconds. If the lock file exists and the timestamp is older than 30 seconds, the lock is considered stale.
- **Contention handling:**
  - If the lock file exists and is fresh (< 30s old): wait 100ms and retry, up to 50 retries (5 seconds max wait).
  - If the lock file exists and is stale (>= 30s old): log a warning ("stealing stale commit lock from PID <pid>, held for <duration>"), delete the lock file, and acquire.
  - If all retries are exhausted: fail with a clear error.
- **Callers:**
  - Orchestrator: architect area writes, manager ticket writes, area hash updates, ticket state transitions, merge queue operations, health cache writes.
  - `scriptorium plan`: spec.md commits at the end of each interactive turn or one-shot invocation.
  - All callers are brief git commit operations. No caller holds the lock for more than the time it takes to stage and commit files.
- **Worktree management is separate:** `ensurePlanWorktree()` runs without locking (idempotent, safe to call concurrently since git worktree operations are atomic). Only the subsequent commit operation acquires the commit lock.

### Lock Hold Patterns

- **Reading areas:** Brief commit lock to snapshot area content at the start of the tick. Done once for all areas.
- **Agent execution:** No lock needed. Manager agents run in threads and produce ticket content in memory.
- **Writing tickets:** Main thread acquires commit lock, writes tickets for one completed manager, commits, releases. Each completed manager's write is a separate lock acquisition.
- The architect still holds the commit lock for its full duration (sequential, runs before managers).

## 18. Concurrency Model

- **Strictly sequential agents:** Architect (reads spec, writes areas, at most once per tick, protected by commit lock, must complete before managers) and Review/Merge (one merge queue item at a time, sequential to guarantee default branch health).
- **Parallel agents (shared slot pool):** Manager (one area per invocation, multiple can run in parallel) and Coding agent (one ticket per invocation, multiple can run in parallel in independent areas). Both share the `maxAgents` slot pool.
- **Interleaved execution:** Managers and coders are interleaved across ticks — the orchestrator does not wait for all managers to finish before starting coders.
- **Merge conflict handling:** Parallel coding agents may produce merge conflicts on shared files. The sequential merge process catches conflicts by merging the default branch into the ticket branch before testing. Conflicting tickets are sent back for another coding attempt with conflict context.
- **Slot arithmetic:** If `maxAgents` is 4 and 2 managers are running, only 2 slots remain for coders (and vice versa).

## 19. Audit Agent

- A read-only audit agent runs when the merge queue fully drains (goes idle after processing one or more items). It does not block the merge queue or modify any code — it only produces a report.
- The audit checks two things:
  1. **Spec compliance**: Read `spec.md` and sample the codebase. Report divergences — features the spec describes that the code doesn't implement, code behaviors not reflected in the spec, contradictions between spec requirements and actual behavior.
  2. **AGENTS.md compliance**: Read `AGENTS.md` and the cumulative diff since the last audit. Report violations of project conventions.
- The orchestrator tracks a "last audited commit" hash. When the merge queue drains, it compares the current default branch HEAD against the last audited commit. If they differ, it spawns the audit agent. If nothing merged, no audit runs.
- Secondary trigger: spec change. If the architect rewrites `spec.md`, an audit runs to catch "spec says X but code still does old-Y".
- The audit agent runs as a background agent using a shared pool slot (like managers/coders).
- The audit agent should be cheap: use a smaller/faster model (default Haiku), limit scope to the cumulative diff since the last audit plus `spec.md` and `AGENTS.md`.
- Output: markdown report written to `.scriptorium/logs/audit/` with a timestamp. Sections for spec drift and AGENTS.md violations, each item citing the relevant rule and the offending code location.
- The audit agent is configured under `agents.audit` in `scriptorium.json`, supporting `harness`, `model`, and `reasoningEffort`. Default model is `claude-haiku-4-5-20251001`.
- `scriptorium audit` CLI command runs the audit agent on demand.

## 20. Compaction-Resilient Agent Context

- When scriptorium builds a continuation prompt for a retry or timeout recovery, re-inject the project's `AGENTS.md` rules (or a condensed version) into the continuation text. The continuation prompt builder has access to the working directory and can read `AGENTS.md`.
- The `continuationPromptBuilder` must be forwarded to `ClaudeCodeRunRequest` in `agent_runner.nim` (currently only forwarded for codex/typoi harnesses).
- Critical `AGENTS.md` rules should be present in `CLAUDE.md` (or `.claude/` config files) for compaction resilience, since Claude Code reloads `CLAUDE.md` after compaction.

## 21. Per-Role Log Persistence

- Agent logs must persist in the repo root under `.scriptorium/logs/` organized by role, not in worktrees that are cleaned up after merge.
- Log directory structure:
  ```
  .scriptorium/logs/
    orchestrator/              # run_*.log (existing, unchanged)
    architect/
      spec/                    # architect spec runs
      areas/                   # architect area generation
    manager/
      <areaId>/                # per-area manager runs
    coder/
      <ticketId>/              # coding agent execution
        attempt-01.jsonl
        attempt-02.jsonl
    prediction/
      <ticketId>/              # difficulty predictions
    review/
      <ticketId>/              # review agent runs
        attempt-01.jsonl
    audit/                     # audit agent reports
  ```
- Review agent: set `logRoot` in `AgentRunRequest` to `repoPath/.scriptorium/logs/review` so JSONL logs persist after worktree cleanup.
- Coding agent: set `logRoot` to `repoPath/.scriptorium/logs/coder` so execution logs persist after worktree cleanup.
- Rename existing log directories to match the consistent per-role structure: `plan-spec/` -> `architect/spec/`, `architect-areas/` -> `architect/areas/`, `<ticketId>-prediction/` -> `prediction/<ticketId>/`.
