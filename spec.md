# Spec

## Adoption Goal

Adopt the existing `scriptorium` repository as the baseline product spec for the current implementation.
This spec describes the behavior that already exists in code and tests so future changes can be evaluated against an explicit preservation target.

## Product Summary

`scriptorium` is a git-native agent orchestration tool for software projects.

- Planning state lives on a dedicated `scriptorium/plan` branch.
- Runtime workflow is Architect -> Manager -> Coding agent -> merge queue.
- Orchestration is local-first and uses git worktrees plus an MCP HTTP server for completion signaling.

## Current-State Requirements

### 1. CLI Surface And Initialization

- The CLI must support: `--init`, `run`, `status`, `plan`, `worktrees`, `--version`, `--help`.
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

### 2. Planning (`scriptorium plan`)

- Planning runs against a managed plan worktree checked out from `scriptorium/plan`.
- Both one-shot (`scriptorium plan <prompt>`) and interactive (`scriptorium plan`) modes must:
  - run the Architect with working directory set to the plan worktree,
  - include repo-root path context so Architect can read source files from the main project,
  - skip git repo checks inside the agent harness for plan worktrees,
  - enforce a post-run write allowlist of `spec.md` only.
- Interactive planning must support:
  - `/show` to print current `spec.md`,
  - `/help` to list commands,
  - `/quit` and `/exit` to leave session,
  - in-memory turn history for the current session,
  - streamed Architect status output during a turn.
- Planning commits:
  - one-shot commits only when `spec.md` changes,
  - interactive commits once per turn that changes `spec.md`.

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
  - runnable `spec.md` (not blank and not placeholder).
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

### 4. Planning Artifacts And State Model

- Plan branch file layout is authoritative:
  - `spec.md`
  - `areas/*.md`
  - `tickets/open/*.md`
  - `tickets/in-progress/*.md`
  - `tickets/done/*.md`
  - `queue/merge/pending/*.md`
  - `queue/merge/active.md`
- Tickets must exist in exactly one state directory at a time.
- Ticket state transitions must be represented by single orchestrator transition commits.
- Ticket IDs in filenames must be monotonic and zero-padded.
- Merge queue item IDs in filenames must also be monotonic and zero-padded.
- Ticket assignment must:
  - move the oldest open ticket to `tickets/in-progress/`,
  - create or reuse a deterministic ticket branch name `scriptorium/ticket-<id>`,
  - create a deterministic managed code worktree path,
  - record worktree metadata in the ticket markdown.
- Area-to-ticket linkage is carried in ticket markdown via `**Area:** <area-id>`.

### 5. Architect, Manager, And Coding Agent Execution

- Area generation and ticket generation are agent-driven:
  - Architect writes area files directly under `areas/`,
  - Manager writes ticket files directly under `tickets/open/`.
- Manager writes are constrained by a write-prefix allowlist to `tickets/open/`.
- Manager execution must also preserve the dirty state of the main repository outside the plan worktree.
- Coding-agent execution must:
  - run in the assigned ticket worktree,
  - receive the ticket path, ticket content, repo path, and worktree path in its prompt,
  - append structured agent run notes to the ticket markdown,
  - persist agent stdout/log file/last-message metadata in those notes,
  - enqueue merge request metadata only when the coding agent calls the MCP `submit_pr` tool.
- Merge-queue enqueueing must use MCP tool state, not stdout scanning.

### 6. Backend Routing And Codex Harness

- Model routing must remain prefix-based:
  - `claude-*` -> `claude-code`
  - `codex-*` and `gpt-*` -> `codex`
  - all other models -> `typoi`
- Current implementation is codex-first:
  - codex backend is implemented,
  - non-codex backends currently fail fast as unimplemented.
- Codex harness must provide:
  - deterministic command shape around `codex exec --json ... --output-last-message ...`,
  - `--dangerously-bypass-approvals-and-sandbox`,
  - optional `--skip-git-repo-check`,
  - MCP server injection through codex config args,
  - JSONL-style run logs,
  - parsed stream events for heartbeat, reasoning, tool, status, and message output,
  - last-message capture,
  - no-output and hard-timeout handling,
  - bounded retry support with a continuation prompt,
  - reasoning-effort normalization for supported codex models.

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
- Stale managed worktrees for non-active tickets must be removable by cleanup.

### 8. Status And Worktree Visibility

- `scriptorium status` must report:
  - open ticket count,
  - in-progress ticket count,
  - done ticket count,
  - active ticket id/path/branch/worktree.
- Active ticket resolution must prefer the active merge-queue item when present, then fall back to the first in-progress ticket worktree.
- `scriptorium worktrees` must list active in-progress ticket worktrees with worktree path, ticket id, and branch mapping.

### 9. Config, Tests, And CI Baseline

- Runtime config file is `scriptorium.json`.
- Config supports:
  - `models.architect`
  - `models.coding`
  - `models.manager`
  - reasoning-effort overrides for architect, coding, and manager
  - `endpoints.local`
  - `logLevel`
- Current code defaults are test-focused:
  - architect, coding, and manager default to `codex-fake-unit-test-model`
  - reasoning-effort defaults are empty
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

- Non-codex harness backends are routed but not yet implemented.
- Ticket execution is single-agent and single-ticket at a time.
- Interactive planning history is in-memory only.
- No dedicated reviewer or merger agent stage exists yet.
- The queue merges directly from ticket worktrees and decides success/failure from local git plus quality-gate results.

## Adoption Acceptance Criteria

- This spec is the preservation baseline for the current repository behavior.
- Future work may change behavior only through explicit spec updates.
- Regression bar:
  - `make test` remains green locally,
  - `make integration-test` remains green in codex-authenticated environments,
  - existing CLI, orchestrator, and merge-queue tests continue to pass.
