# Spec

## Adoption Goal

Adopt the existing `scriptorium` repository as the preservation baseline for the current implementation.
This spec describes behavior that is present in the code and covered by current tests so future changes can be evaluated against an explicit live-state contract.

## Product Summary

`scriptorium` is a git-native agent orchestration tool for software projects.

- Planning state lives on a dedicated `scriptorium/plan` branch.
- Runtime workflow is Architect -> Manager -> Coding agent -> merge queue.
- Orchestration is local-first and uses deterministic managed git worktrees plus an MCP HTTP server for completion signaling.

## Current-State Requirements

### 1. CLI Surface And Initialization

- The CLI must support: `--init`, `run`, `status`, `plan`, `ask`, `worktrees`, `--version`, `--help`.
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

### 2. Planning And Ask Sessions

- Planning runs against a managed plan worktree checked out from `scriptorium/plan`.
- The managed plan worktree path must be deterministic under `/tmp/scriptorium/.../worktrees/plan`.
- Both one-shot (`scriptorium plan <prompt>`) and interactive (`scriptorium plan`) planning must:
  - run the Architect with working directory set to the managed plan worktree,
  - include repo-root path context so the Architect can read source files from the main project,
  - skip git repo checks inside the agent harness for plan worktrees,
  - enforce a post-run write allowlist of `spec.md` only,
  - use an Architect-specific per-repository lock so concurrent planner or manager writes fail fast.
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

### 3. Orchestrator Run Loop

- `scriptorium run` must start:
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
- If spec is not runnable, orchestrator must log:
  - `WAITING: no spec — run 'scriptorium plan'`
- Tick order must remain:
  1. architect area generation when areas are missing,
  2. manager ticket generation for areas without open or in-progress tickets,
  3. assign and execute the oldest open ticket,
  4. process at most one merge-queue item.
- The orchestrator must cache `master` health by `master` HEAD commit and recompute only when `master` changes.

### 4. Planning Artifacts And State Model

- Plan branch file layout is authoritative:
  - `spec.md`
  - `areas/*.md`
  - `tickets/open/*.md`
  - `tickets/in-progress/*.md`
  - `tickets/done/*.md`
  - `queue/merge/pending/*.md`
  - `queue/merge/active.md`
- `queue/merge/` may be created lazily by orchestrator queue initialization rather than by `--init`.
- Tickets must exist in exactly one state directory at a time.
- Ticket state transitions must be represented by single orchestrator transition commits.
- Ticket IDs in filenames must be monotonic and zero-padded.
- Merge queue item IDs in filenames must also be monotonic and zero-padded.
- Area IDs are derived from area markdown filenames.
- Area-to-ticket linkage is carried in ticket markdown via `**Area:** <area-id>`.
- Ticket assignment must:
  - move the oldest open ticket to `tickets/in-progress/`,
  - create or reuse deterministic ticket branch name `scriptorium/ticket-<id>`,
  - create a deterministic managed code worktree path under `/tmp/scriptorium/.../worktrees/tickets/`,
  - record worktree metadata in ticket markdown via `**Worktree:** <absolute-path>`.
- Active merge queue metadata must store:
  - ticket path,
  - ticket id,
  - branch,
  - worktree,
  - summary.

### 5. Architect, Manager, And Coding Agent Execution

- Area generation and ticket generation are agent-driven:
  - Architect writes area files directly under `areas/`,
  - Manager writes ticket files directly under `tickets/open/`.
- Architect area generation must only run when:
  - `spec.md` is runnable,
  - no area markdown files exist.
- Manager ticket generation must only run for areas without open or in-progress tickets.
- Manager writes are constrained by a write-prefix allowlist to `tickets/open/`.
- Manager execution must preserve the dirty state of the main repository outside the plan worktree.
- Manager-generated ticket filenames must be assigned by the orchestrator, not by the agent prompt output.
- Coding-agent execution must:
  - run in the assigned ticket worktree,
  - receive the ticket path, ticket content, repo path, and worktree path in its prompt,
  - append structured agent run notes to the ticket markdown,
  - persist backend, exit code, attempt, attempt count, timeout, log file, last-message file, last message tail, and stdout tail in those notes,
  - enqueue merge request metadata only when the coding agent calls the MCP `submit_pr` tool.
- Merge-queue enqueueing must use MCP tool state, not stdout scanning.

### 6. Harness Routing And Agent Backends

- Runtime agent configuration is role-based and stored under `scriptorium.json` `agents`:
  - `agents.architect`
  - `agents.coding`
  - `agents.manager`
- Each role config supports:
  - `harness`
  - `model`
  - `reasoningEffort`
- Model-prefix harness inference must remain:
  - `claude-*` -> `claude-code`
  - `codex-*` and `gpt-*` -> `codex`
  - all other models -> `typoi`
- Current backend implementation state is:
  - `codex` implemented,
  - `claude-code` implemented,
  - `typoi` routed but fails fast as unimplemented.
- The role config may explicitly set `harness` instead of relying on model-prefix inference.
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

### 7. Merge Queue Safety Contract

- Merge queue is single-flight; each processing pass handles at most one pending item.
- Queue processing must:
  - ensure queue metadata exists,
  - set `queue/merge/active.md` to the currently processed pending item,
  - merge `master` into the ticket branch worktree,
  - run required quality targets in the ticket worktree:
    - `make test`
    - `make integration-test`
  - on success, fast-forward merge the ticket branch into `master`,
  - on success, append a merge success note and move ticket `in-progress -> done`,
  - on failure, append a merge failure note and move ticket `in-progress -> open`.
- Queue metadata must be cleaned up after success, failure, or terminal stale-item cleanup.
- If a pending queue item references a ticket already moved to `open` or `done`, queue processing must remove the stale queue item and clear active metadata.
- Merge queue success and failure notes must include the submit summary and relevant output tails.
- Stale managed worktrees for non-active tickets must be removable by cleanup.
- Legacy repo-local managed worktrees under `.scriptorium/worktrees` must be removable by cleanup and assignment flows.

### 8. Status, Worktree Visibility, And Managed Paths

- `scriptorium status` must report:
  - open ticket count,
  - in-progress ticket count,
  - done ticket count,
  - active ticket id/path/branch/worktree.
- If there is no active ticket, `status` must print `Active Agent: none`.
- Active ticket resolution must prefer the active merge-queue item when present, then fall back to the first in-progress ticket worktree.
- `scriptorium worktrees` must list active in-progress ticket worktrees with worktree path, ticket id, and branch mapping.
- If no in-progress ticket worktrees exist, `scriptorium worktrees` must print:
  - `scriptorium: no active ticket worktrees`
- Managed repository state must live in deterministic per-repo paths under `/tmp/scriptorium/`.
- Managed state must include:
  - worktrees,
  - repository lock state.

### 9. Config, Logging, Tests, And CI Baseline

- Runtime config file is `scriptorium.json`.
- Config supports:
  - `agents.architect.harness`
  - `agents.architect.model`
  - `agents.architect.reasoningEffort`
  - `agents.coding.harness`
  - `agents.coding.model`
  - `agents.coding.reasoningEffort`
  - `agents.manager.harness`
  - `agents.manager.model`
  - `agents.manager.reasoningEffort`
  - `endpoints.local`
  - `logLevel`
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

## Known Current Limitations

- `typoi` is routed but not implemented.
- Ticket execution is single-agent and single-ticket at a time.
- Interactive planning and ask history are in-memory only.
- No dedicated reviewer or merger agent stage exists yet.
- The queue merges directly from ticket worktrees and decides success or failure from local git plus required quality-gate results.

## Adoption Acceptance Criteria

- This spec is the preservation baseline for current repository behavior.
- Future work may change behavior only through explicit spec updates.
- Regression bar:
  - `make test` remains green locally,
  - `make integration-test` remains green in authenticated live-harness environments,
  - existing CLI, orchestrator, harness, and merge-queue tests continue to pass.
- V2 regression bar: all v1 acceptance criteria remain, plus stall detection and log forwarding tests pass.

## V2 Features

### 10. Coding Agent Log Forwarding

- During coding agent execution, the orchestrator must forward meaningful stream events from the agent harness to orchestrator logs in real time.
- For both claude-code (stream-json) and codex (--json) harnesses, the following event types must be surfaced:
  - Tool calls: log the tool name and a summary of arguments (e.g., "agent: tool edit_file src/foo.nim").
  - File activity: log file reads and writes detected from tool events.
  - Status changes: log agent status transitions (e.g., "agent: thinking", "agent: executing tool").
- The orchestrator must use the existing AgentEventHandler callback to receive parsed stream events during agent execution.
- Log output must be prefixed with the ticket ID for correlation.
- Acceptance criteria:
  - When a coding agent runs, the orchestrator logs show tool calls and file activity as they happen.
  - Log lines include ticket ID prefix.
  - No new event types need to be invented — use existing heartbeat, reasoning, tool, status, and message event categories.

### 11. Stall Detection And Automatic Continuation

- A "stall" is defined as: a coding agent turn completes (process exits) without having called the submit_pr MCP tool.
- When a stall is detected, the orchestrator must automatically retry the agent with a continuation prompt that includes:
  - The full original ticket content.
  - A reminder to continue working and call submit_pr when done.
- Stall-driven retries must use the existing bounded retry mechanism (maxAttempts in AgentRunRequest).
- The continuation prompt must be distinct from the initial prompt — it must indicate this is a retry after a stall.
- Each stall retry must be logged with the attempt number.
- Acceptance criteria:
  - When a coding agent exits without calling submit_pr, the orchestrator retries with the continuation prompt.
  - Retries stop after maxAttempts is reached.
  - Each retry is logged with attempt number and ticket ID.
  - The continuation prompt includes the original ticket content.

### 12. Test-Aware Stall Detection

- When a stall is detected (turn ended, no submit_pr called), before sending the continuation prompt the orchestrator must:
  - Run make test in the agent's worktree.
  - Capture the exit code and output.
- If tests fail, the continuation prompt must include:
  - The test failure output (truncated to a reasonable limit if very long).
  - A directive to fix the failing tests before submitting.
- If tests pass, the continuation prompt must still include:
  - A note that tests are passing.
  - A directive to continue working and submit the PR.
- Acceptance criteria:
  - On stall, make test runs in the agent worktree before retry.
  - Test failure output is included in the continuation prompt when tests fail.
  - Test pass status is included in the continuation prompt when tests pass.
  - The existing stall detection behavior from section 11 is preserved — test-aware detection augments it, not replaces it.

## V2 Known Limitations

- Stall detection is per-turn only — it does not detect agents that are running but making no progress within a turn.
- Test-aware stall detection runs make test only, not make integration-test.
- Coding agent promotions and manager-driven retries are out of scope for v2.
