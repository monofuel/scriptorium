# Spec

## Adoption Goal

Adopt the existing `scriptorium` repository as the baseline product spec for V1.  
This spec captures the behavior that already exists in code and tests so future work can extend it without regressing core orchestration guarantees.

## Product Summary

`scriptorium` is a git-native agent orchestration tool for software projects.

- Planning state lives on a dedicated `scriptorium/plan` branch.
- Runtime workflow is Architect -> Manager -> Coding agent -> merge queue.
- Merges to `master` are gated by `make test` and queue processing rules.

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
  - create an initial commit on the plan branch.

### 2. Planning (`scriptorium plan`)

- Planning runs against a temporary worktree checked out from `scriptorium/plan`.
- Both one-shot (`scriptorium plan <prompt>`) and interactive (`scriptorium plan`) modes must:
  - run the Architect with working directory set to the plan worktree,
  - include repo-root path context so Architect can read source files from the main project,
  - enforce a post-run write allowlist of `spec.md` only.
- Interactive planning must support:
  - `/show` to print current `spec.md`,
  - `/help` to list commands,
  - `/quit` (and `/exit`) to leave session.
- Planning commits:
  - one-shot commits only when `spec.md` changes,
  - interactive commits once per turn that changes `spec.md`.

### 3. Orchestrator Run Loop

- `scriptorium run` must start the orchestrator loop and local MCP HTTP server.
- Endpoint source: `scriptorium.json` `endpoints.local`, defaulting to `http://127.0.0.1:8097`.
- Polling is continuous with idle sleep between ticks.
- Work must be gated by:
  - existence of `scriptorium/plan` branch,
  - healthy `master` (`make test` on master worktree),
  - runnable `spec.md` (not blank and not placeholder).
- If spec is not runnable, orchestrator must log:
  - `WAITING: no spec — run 'scriptorium plan'`
- Tick order must remain:
  1. architect area generation (when areas are missing),
  2. manager ticket generation (for areas without open/in-progress tickets),
  3. assign and execute oldest open ticket,
  4. process one merge-queue item.

### 4. Planning Artifacts And State Model

- Plan branch file layout is authoritative:
  - `spec.md`
  - `areas/*.md`
  - `tickets/open/*.md`
  - `tickets/in-progress/*.md`
  - `tickets/done/*.md`
  - `queue/merge/pending/*.md`
  - `queue/merge/active.md`
- Tickets must be in exactly one state directory at a time.
- Ticket state transitions must be single orchestrator commits (no partial moves).
- Ticket IDs in filenames must be monotonic and zero-padded.
- Ticket assignment must move oldest open ticket to `in-progress` and attach worktree metadata.

### 5. Agent Execution And Backend Routing

- Model routing must remain prefix-based:
  - `claude-*` -> `claude-code`
  - `codex-*` / `gpt-*` -> `codex`
  - other -> `typoi`
- Current implementation is codex-first:
  - codex backend is implemented,
  - non-codex backends are currently not implemented and fail fast.
- Coding-agent execution must:
  - run in ticket worktree,
  - append structured agent run notes to ticket markdown,
  - detect `submit_pr("...")` in agent output and enqueue merge request metadata.
- Codex harness must provide:
  - deterministic command shape (`codex exec --json ... --output-last-message ...`),
  - JSONL run logs,
  - last-message capture,
  - no-output and hard timeout handling,
  - bounded retry support with continuation prompt.

### 6. Merge Queue Safety Contract

- Merge queue is single-flight; each processing pass handles at most one pending item.
- For each queue item:
  - merge `master` into ticket branch worktree,
  - run `make test` in ticket worktree,
  - on success, fast-forward merge ticket branch into `master`,
  - on success, move ticket `in-progress -> done` and append success note,
  - on failure, move ticket `in-progress -> open` and append failure note.
- Queue metadata (`pending` and `active`) must be cleaned up after success/failure handling.
- Stale managed worktrees for non-active tickets must be removable by cleanup.

### 7. Status And Worktree Visibility

- `scriptorium status` must report:
  - open/in-progress/done ticket counts,
  - active ticket id/path/branch/worktree (from queue active item or in-progress worktree fallback).
- `scriptorium worktrees` must list active ticket worktrees with ticket and branch mapping.

### 8. Config, Test, And CI Baseline

- Runtime config file is `scriptorium.json`.
- Config supports:
  - `models.architect`
  - `models.coding`
  - `endpoints.local`
- Current code defaults are test-focused (`codex-fake-unit-test-model` for architect/coding) and should be overridden in real usage.
- Test commands:
  - `make test` runs `tests/test_*.nim` (local, no API key requirement),
  - `make integration-test` runs `tests/integration_*.nim` (codex/auth required).
- CI baseline:
  - build workflow runs unit tests on push/PR and builds linux binary on push,
  - integration workflow runs on `master` push and `workflow_dispatch` with codex/auth setup.

## Known Current Limitations

- Non-codex harness backends are routed but not yet implemented.
- Ticket execution is single-agent / single-ticket at a time (no parallel coding workers).
- Interactive planning history is in-memory only (no resume/persistence).
- No dedicated reviewer/merger agent stage yet; queue logic performs merge decisions directly.

## Adoption Acceptance Criteria

- This spec is the preservation baseline for current V1 behavior.
- Future work may change behavior only through explicit spec updates.
- Regression bar:
  - `make test` remains green locally,
  - integration tests remain green in codex-authenticated environments.
