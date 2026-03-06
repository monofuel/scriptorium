# E2E Debugging

This document explains how to monitor and debug live end-to-end tests while they are running.

## Scope

These notes apply to live E2E tests such as:

- `tests/e2e_euler_live.nim`

They also apply to other live integration tests that use the same fixture helpers under `tests/support/`.

## Main Runtime Locations

### Fixture Repository

The generated fixture repository lives under:

```text
/tmp/scriptorium/integration/<case-name>_<suffix>
```

Example:

```text
/tmp/scriptorium/integration/scriptorium_integration_live_euler_abcd1234
```

This is the project repository root for the live test fixture. It usually contains:

- `.git/`
- `AGENTS.md`
- `Makefile`
- `scriptorium.json`

During the test, this path is the repo whose `master` branch is being orchestrated.

### Orchestrator Session Logs

The orchestrator writes a human-readable session log under:

```text
/tmp/scriptorium/<fixture-repo-name>/run_<timestamp>.log
```

Example:

```text
/tmp/scriptorium/scriptorium_integration_live_euler_abcd1234/run_2026-03-06T01-54-50Z.log
```

This is the best high-level place to watch end-to-end progress.

### Managed State Root

Scriptorium creates managed worktrees and locks under:

```text
/tmp/scriptorium/<fixture-repo-name>-<repo-hash>/
```

Example:

```text
/tmp/scriptorium/scriptorium_integration_live_euler_abcd1234-7bbe8b7190c3b861/
```

Typical contents:

- `locks/repo.lock/`
- `worktrees/plan/`
- `worktrees/tickets/<ticket-name>/`

### Plan-Agent Codex Logs

Architect and Manager Codex runs write logs outside the plan worktree under:

```text
/tmp/scriptorium-plan-logs/
```

Examples:

```text
/tmp/scriptorium-plan-logs/architect-areas/architect-areas/attempt-01.jsonl
/tmp/scriptorium-plan-logs/manager/<area-id>/manager-<area-id>/attempt-01.jsonl
```

### Coding-Agent Codex Logs

The Coding agent writes logs inside the assigned ticket worktree:

```text
/tmp/scriptorium/<fixture-repo-name>-<repo-hash>/worktrees/tickets/<ticket-name>/.scriptorium/logs/<ticket-id>/
```

Typical files:

- `attempt-01.jsonl`
- `attempt-01.last_message.txt`

## What To Watch

### High-Level Progress

Tail the orchestrator log:

```bash
tail -f /tmp/scriptorium/<fixture-repo-name>/run_*.log
```

Key milestones to look for:

- `running architect`
- `architect: areas updated`
- `running manager`
- `manager: tickets created`
- `running coding agent`
- `coding agent called submit_pr`
- `merge queue: item processed`

### Plan Branch State

Inspect the plan branch tree:

```bash
git -C /tmp/scriptorium/integration/<fixture-repo> ls-tree -r --name-only scriptorium/plan
```

You should see the progression:

- `areas/*.md`
- `tickets/open/*.md`
- `tickets/in-progress/*.md`
- `tickets/done/*.md`
- `queue/merge/...`

Useful watch command:

```bash
watch -n 2 'git -C /tmp/scriptorium/integration/<fixture-repo> ls-tree -r --name-only scriptorium/plan'
```

### Final Artifact On Master

Check whether the expected file landed on `master`:

```bash
git -C /tmp/scriptorium/integration/<fixture-repo> show master:multiples.nim
```

### Live Codex Activity

Look for active Codex processes:

```bash
ps -ef | rg 'codex|scriptorium_integration_live'
```

This helps confirm whether Architect, Manager, or Coding is still running.

## Useful Debug Commands

### Find The Latest Live Euler Fixture

```bash
find /tmp/scriptorium/integration -maxdepth 1 -mindepth 1 -type d -name 'scriptorium_integration_live_euler_*' | sort | tail -n 1
```

### Find The Latest Orchestrator Log For A Fixture

```bash
find /tmp/scriptorium/<fixture-repo-name> -maxdepth 1 -type f -name 'run_*.log' | sort | tail -n 1
```

### Inspect Architect JSONL Output

```bash
tail -n 120 /tmp/scriptorium-plan-logs/architect-areas/architect-areas/attempt-01.jsonl
```

### Inspect Manager JSONL Output

```bash
tail -n 120 /tmp/scriptorium-plan-logs/manager/<area-id>/manager-<area-id>/attempt-01.jsonl
```

### Inspect Coding-Agent JSONL Output

```bash
tail -n 200 /tmp/scriptorium/<fixture-repo-name>-<repo-hash>/worktrees/tickets/<ticket-name>/.scriptorium/logs/<ticket-id>/attempt-01.jsonl
```

## Expected Folder Progression

### Before Architect

The plan branch usually contains only:

- `spec.md`
- `areas/.gitkeep`
- `tickets/open/.gitkeep`
- `tickets/in-progress/.gitkeep`
- `tickets/done/.gitkeep`

### After Architect

You should see at least one area file:

- `areas/<something>.md`

### After Manager

You should see at least one open ticket:

- `tickets/open/0001-<slug>.md`

### After Assignment

You should see:

- `tickets/in-progress/0001-<slug>.md`
- a managed ticket worktree under `/tmp/scriptorium/<fixture-repo-name>-<repo-hash>/worktrees/tickets/`

### After Successful Merge

You should see:

- `tickets/done/0001-<slug>.md`
- `queue/merge/active.md` cleared
- pending queue emptied
- expected artifact on `master`

## Common Failure Patterns

### Prompt Path Confusion

Symptoms:

- Codex spends time trying to locate `AGENTS.md`, `spec.md`, or worktree files.
- JSONL logs show recovery chatter before actual work begins.

Primary places to inspect:

- prompt templates under `src/scriptorium/prompts/`
- orchestrator prompt builders in `src/scriptorium/orchestrator.nim`
- Architect or Manager JSONL logs

### Write Guard Failures

Symptoms:

- Orchestrator log shows `modified out-of-scope files`.

Primary places to inspect:

- orchestrator log
- plan-agent JSONL log
- write-allowlist logic in `src/scriptorium/orchestrator.nim`

### Missing `submit_pr`

Symptoms:

- Coding agent appears to finish, but no merge queue item is created.
- Ticket remains in `in-progress`.

Primary places to inspect:

- coding-agent JSONL log
- orchestrator log
- final ticket content in `tickets/in-progress/*.md`

### Quality Gate Failures

Symptoms:

- Merge queue reopens the ticket.
- Ticket gets a `Merge Queue Failure` note.

Primary places to inspect:

- orchestrator log
- final ticket markdown on `scriptorium/plan`
- `make test` and `make integration-test` behavior in the fixture repo

## Notes

- The fixture repo is usually removed automatically after the test process exits.
- If you need to inspect a live run, do it while the test is still active.
- The orchestrator log under `/tmp/scriptorium/<fixture-repo-name>/` usually survives long enough to inspect even if the fixture repo is later removed.
