# scriptorium

Git-native agent orchestration for software projects.

Scriptorium keeps planning and execution state in Git, runs a strict Architect → Manager → Coding → Review workflow, and merges work only when `master` stays green.

Path and workflow terminology is defined in `docs/terms.md`.

WARNING: this is a work in progress and is not yet ready for general use.
there is no warrenty, it is highly experimental, letting agents run loose is a bad idea but this is still a fun project. you should probably run this is a container.

## Status

Current features:
- CLI commands: `--init`, `run`, `status`, `plan`, `ask`, `worktrees`, `--version`, `--help`
- Architect → Manager → Coding → Review agent workflow
- Parallel coding agents with area-based conflict avoidance
- Ticket dependencies (`**Depends:**` field — tickets with unsatisfied deps are skipped)
- Rate limit detection with exponential backoff and concurrency reduction
- Token budget tracking to pause new assignments when stdout bytes exceed limit
- Stuck ticket parking after repeated failures
- Configurable timeouts, retry limits, and concurrency
- Merge safety with test gates and merge queue
- Codex and Claude Code agent harnesses

## Core workflow

At a high level:

1. Engineer creates or revises `spec.md` with `scriptorium plan`.
2. Orchestrator reads `spec.md` and generates `areas/*.md` (Architect).
3. Orchestrator generates `tickets/open/*.md` from areas (Manager).
4. Open tickets are assigned to deterministic `/tmp/scriptorium/<repo-key>/worktrees/tickets/<ticket>/` worktrees and moved to `tickets/in-progress/`. Multiple tickets are assigned concurrently when they touch independent areas.
   - Tickets with unsatisfied `**Depends:**` references are skipped until their dependencies reach `done/`.
5. Coding agent implements the ticket and calls the `submit_pr` MCP tool with a summary.
6. Review agent evaluates the changes — approves or requests changes. Rejected work gets a new coding session with feedback.
7. Merge queue processes one item at a time:
   - merge `master` into ticket branch
   - run `make test` and `make integration-test` in ticket worktree
   - on pass: fast-forward merge to `master`, move ticket to `tickets/done/`
   - on fail: move ticket back to `tickets/open/` and append failure notes
   - on repeated failures: park ticket in `tickets/stuck/`

If `spec.md` is missing or still the placeholder, the loop idles and logs:
`WAITING: no spec — run 'scriptorium plan'`

## Quick start

### 1) Prerequisites

- Nim >= 2.0.0
- Git
- `make`
- Codex CLI and Claude Code CLI for integration/e2e runs (`npm i -g @openai/codex @anthropic-ai/claude-code`)

### 2) Build

```bash
nimby sync -g nimby.lock
make build
```

### 3) Initialize a repo

From your project root:

```bash
scriptorium --init
```

This creates the orphan branch `scriptorium/plan` with base planning structure.

### 4) Configure agents (optional but recommended)

Create `scriptorium.json` in repo root:

```json
{
  "agents": {
    "architect": { "harness": "codex", "model": "gpt-5.1-codex-mini", "reasoningEffort": "medium" },
    "coding":    { "harness": "codex", "model": "gpt-5.1-codex-mini", "reasoningEffort": "high" },
    "manager":   { "harness": "codex", "model": "gpt-5.1-codex-mini", "reasoningEffort": "high" },
    "reviewer":  { "harness": "codex", "model": "gpt-5.1-codex-mini", "reasoningEffort": "medium" }
  },
  "endpoints": {
    "local": "http://127.0.0.1:8097"
  },
  "concurrency": {
    "maxAgents": 4,
    "tokenBudgetMB": 100
  },
  "timeouts": {
    "codingAgentHardTimeoutMs": 14400000,
    "codingAgentNoOutputTimeoutMs": 300000,
    "codingAgentMaxAttempts": 5
  },
  "logLevel": "INFO",
  "fileLogLevel": "DEBUG"
}
```

Notes:
- Each agent has `harness`, `model`, and `reasoningEffort` fields.
- Harness routing is prefix-based: `claude-*` → claude-code harness, `gpt-*` / `codex-*` → codex harness.
- `concurrency.maxAgents` controls parallel coding agents (default 1).
- `concurrency.tokenBudgetMB` caps cumulative stdout bytes before pausing new assignments (default 0 = unlimited).
- Timeout defaults: 4h hard timeout, 5min no-output timeout, 5 max attempts.
- `endpoints.local` defaults to `http://127.0.0.1:8097` when omitted.
- `logLevel` / `fileLogLevel` can be overridden via `SCRIPTORIUM_LOG_LEVEL` / `SCRIPTORIUM_FILE_LOG_LEVEL` environment variables.

### 5) Build the spec

Interactive mode:

```bash
scriptorium plan
```

One-shot mode:

```bash
scriptorium plan "Add CI checks for merge queue invariants"
```

Planning execution model (both modes):
- Architect runs in a deterministic `/tmp/scriptorium/<repo-key>/worktrees/plan` worktree.
- Prompt includes repo-root path so Architect can read project source.
- Post-run write guard allows only `spec.md`; any other file edits fail the command.
- Planner/manager writes are single-flight via `/tmp/scriptorium/<repo-key>/locks/repo.lock`; concurrent planner/manager runs fail fast.

Interactive planning commands:
- `/show` prints current `spec.md`
- `/help` lists commands
- `/quit` exits

### 6) Run orchestrator

```bash
scriptorium run
```

Runtime quality gates:
- Master health runs `make test` and `make integration-test` on `master` before scheduling work.
- Merge queue runs the same two targets in each ticket worktree before fast-forwarding into `master`.

### 7) Logging

`scriptorium run` writes a human-readable log file per session to:

```text
/tmp/scriptorium/{project_name}/run_{datetime}.log
```

- `{project_name}` is the repo directory name (e.g. `scriptorium`)
- `{datetime}` is a UTC timestamp like `2026-02-28T14-30-00Z`
- The directory is created automatically on startup

Every log line is written to both stdout and the log file with the format:

```text
[2026-02-28T14:30:00Z] [INFO] orchestrator listening on http://127.0.0.1:8097
```

Log levels: `DEBUG`, `INFO`, `WARN`, `ERROR`. Logged events include orchestrator startup, tick activity, architect/manager/coding-agent results, merge queue processing, master health checks, and shutdown signals.

To follow a live session:

```bash
tail -f /tmp/scriptorium/myproject/run_*.log
```

## CLI reference

```text
scriptorium --init [path]    Initialize workspace
scriptorium run              Start orchestrator daemon
scriptorium status           Show ticket counts and active agent info
scriptorium plan             Interactive Architect planning session
scriptorium plan <prompt>    One-shot spec update
scriptorium ask              Interactive read-only Q&A with the Architect
scriptorium worktrees        List active ticket worktrees
scriptorium --version        Print version
scriptorium --help           Show help
```

## Plan branch layout

`scriptorium/plan` is the planning database. State is files + commits.

```text
spec.md
areas/
tickets/
  open/
  in-progress/
  done/
  stuck/
decisions/
queue/
  merge/
    pending/
    active.md
```

Key invariants:
- A ticket exists in exactly one state directory.
- Ticket state transitions are single orchestrator commits.
- No partial ticket moves are allowed.

## Testing

Local unit tests:

```bash
make test
```

- Runs `tests/test_*.nim`
- No network/API keys required

Integration tests:

```bash
make integration-test
```

- Runs `tests/integration_*.nim`
- Uses real codex and claude-code execution for harness coverage
- Requires:
  - `codex` and `claude` binaries on `PATH`
  - Codex auth: `OPENAI_API_KEY` / `CODEX_API_KEY`, or Codex OAuth (no API key needed)
  - Claude auth: `ANTHROPIC_API_KEY`, or Claude CLI OAuth (no API key needed)
  - CI uses API key secrets; local development can use either approach

Live end-to-end tests:

```bash
make e2e-test
```

- Runs `tests/e2e_*.nim`
- Uses real codex and claude-code execution and full orchestrator flows
- Requires the same auth prerequisites as integration tests

## CI

- `.github/workflows/build.yml`
  - Trigger: `push`, `pull_request`
  - Runs: `make test`

- `.github/workflows/integration.yml`
  - Trigger: `push` to `master`, `workflow_dispatch`
  - Installs `@openai/codex` and `@anthropic-ai/claude-code`
  - Runs: `make integration-test`
  - Uses repo secrets `OPENAI_API_KEY` and `ANTHROPIC_API_KEY`

- `.github/workflows/e2e.yml`
  - Trigger: `push` to `master`, `workflow_dispatch`
  - Installs `@openai/codex` and `@anthropic-ai/claude-code`
  - Runs: `make e2e-test`
  - Uses repo secrets `OPENAI_API_KEY` and `ANTHROPIC_API_KEY`
  - Uploads debug artifacts on failure (`/tmp/scriptorium`, `/tmp/scriptorium-plan-logs`)

This split keeps PR CI safe while still running key-backed integration and e2e coverage on trusted `master` pushes.

## Future plans

V6 focus areas (see `docs/v6.md` for details):
- Prediction prompt calibration — duration estimates are consistently ~2x too high, need historical timing data as calibration context.
- MCP tool timing reliability — `submit_pr` sometimes unavailable on first attempt due to race conditions in MCP server startup.
- Merge queue conflict handling — handle master divergence gracefully (rebase or retry) instead of failing on ff-only merge.
- Review agent prompt improvements — review agent tends to stall and default-approve; needs investigation into prompt and MCP tool discovery issues.

## License

MIT. See `LICENSE`.
