# Spec

## Adoption Goal

Adopt the existing `scriptorium` repository as the preservation baseline for the current implementation.
This spec describes behavior that is present in the code and covered by current tests so future changes can be evaluated against an explicit live-state contract.

## Product Summary

`scriptorium` is a git-native agent orchestration tool for software projects.

- Planning state lives on a dedicated `scriptorium/plan` branch.
- Runtime workflow is Architect -> Manager -> Coding agent -> Review agent -> merge queue.
- Orchestration is local-first and uses deterministic managed git worktrees plus an MCP HTTP server for completion signaling.

## Current-State Requirements

### 1. CLI Surface And Initialization

- The CLI must support: `--init`, `run`, `status`, `plan`, `ask`, `do`, `audit`, `dashboard`, `discord`, `mattermost`, `sync`, `worktrees`, `--version`, `--help`.
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
- Areas are persistent ownership zones that evolve with the spec, not one-shot artifacts; the architect updates or creates area files whenever `spec.md` changes, and the manager re-tickets areas whose content has changed.
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
- Architect area generation is continuous and content-hash driven:
  - `spec.md` must be runnable,
  - the orchestrator stores a SHA-1 hash of `spec.md` in `areas/.spec-hash`,
  - on first run (no `.spec-hash` marker), the architect generates areas and writes the marker,
  - on subsequent ticks, the architect re-runs only when the current `spec.md` hash differs from the stored hash,
  - after area generation, the orchestrator updates `areas/.spec-hash` and commits the marker separately,
  - if areas already exist but no `.spec-hash` marker is present (migration), the orchestrator writes the marker from the current spec without re-running the architect.
- Manager ticket generation is continuous and content-hash driven:
  - the orchestrator stores per-area SHA-1 hashes in `tickets/.area-hashes` (tab/colon-separated `area-id:hash`, one per line, sorted),
  - areas with open or in-progress tickets are always suppressed (blocks concurrent work on the same area),
  - when `tickets/.area-hashes` exists, areas whose content hash differs from the stored hash are eligible for re-ticketing, even if previous tickets for that area are done,
  - when `tickets/.area-hashes` does not exist (legacy fallback), areas with any ticket in any state are suppressed,
  - after ticket generation, the orchestrator computes and writes hashes for all current areas and commits the hash file separately.
- Manager execution is batched: all eligible areas are included in a single agent prompt and session.
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
  - `agents.architect.hardTimeout`
  - `agents.architect.noOutputTimeout`
  - `agents.architect.progressTimeout`
  - `agents.coding.harness`
  - `agents.coding.model`
  - `agents.coding.reasoningEffort`
  - `agents.coding.hardTimeout`
  - `agents.coding.noOutputTimeout`
  - `agents.coding.progressTimeout`
  - `agents.manager.harness`
  - `agents.manager.model`
  - `agents.manager.reasoningEffort`
  - `agents.manager.hardTimeout`
  - `agents.manager.noOutputTimeout`
  - `agents.manager.progressTimeout`
  - `agents.reviewer.harness`
  - `agents.reviewer.model`
  - `agents.reviewer.reasoningEffort`
  - `agents.reviewer.hardTimeout`
  - `agents.reviewer.noOutputTimeout`
  - `agents.reviewer.progressTimeout`
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
- Ticket execution is single-agent and single-ticket at a time (addressed in v5, sections 23-26).
- Interactive planning and ask history are in-memory only.
- No dedicated reviewer or merger agent stage exists yet (addressed in v4, section 21).
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

### 10. Agent Log Forwarding

- During all agent execution (coding, manager, architect, and review), the orchestrator must forward meaningful stream events from the agent harness to orchestrator logs in real time.
- For both claude-code (stream-json) and codex (--json) harnesses, the following event types must be surfaced:
  - Tool calls: log the tool name and a summary of arguments (e.g., "agent: tool edit_file src/foo.nim").
  - File activity: log file reads and writes detected from tool events.
  - Status changes: log agent status transitions (e.g., "agent: thinking", "agent: executing tool").
- The orchestrator must use the existing AgentEventHandler callback to receive parsed stream events during agent execution.
- Log output must be prefixed with the agent role and relevant identifier (ticket ID, area ID, etc.) for correlation.
- Acceptance criteria:
  - When any agent runs, the orchestrator logs show tool calls and file activity as they happen.
  - Log lines include agent role and identifier prefix.
  - No new event types need to be invented — use existing heartbeat, reasoning, tool, status, and message event categories.

### 11. Stall Detection And Automatic Continuation

- Stall detection applies to **all** agent roles — coding, manager, architect, and review agents. Every agent execution must be monitored for stalls.
- A "stall" is defined per role as: an agent turn completes (process exits) without having called its expected completion signal:
  - **Coding agent:** exits without calling the `submit_pr` MCP tool.
  - **Review agent:** exits without calling the `submit_review` MCP tool (see section 21 for review-specific stall policy).
  - **Manager agent:** exits without producing any ticket files in `tickets/open/`, or exceeds its hard timeout.
  - **Architect agent:** exits without producing or updating any area files in `areas/`, or exceeds its hard timeout.
- When a stall is detected, the orchestrator must automatically retry the agent with a continuation prompt that includes:
  - The full original prompt content (ticket content for coding/review, area list for manager, spec for architect).
  - A reminder to continue working and complete the expected action.
- Stall-driven retries must use the existing bounded retry mechanism (maxAttempts in AgentRunRequest).
- The continuation prompt must be distinct from the initial prompt — it must indicate this is a retry after a stall.
- Each stall retry must be logged with the attempt number and agent role.
- Hard timeout and no-output timeout apply to all agent roles as baseline safety nets, not just coding agents. These timeouts are configurable per role via `agents.<role>.hardTimeout` and `agents.<role>.noOutputTimeout` in `scriptorium.json`.
- Acceptance criteria:
  - When any agent exits without completing its expected action, the orchestrator retries with the continuation prompt.
  - Retries stop after maxAttempts is reached.
  - Each retry is logged with attempt number, agent role, and relevant identifier (ticket ID, area ID, etc.).
  - The continuation prompt includes the original prompt content.
  - Manager and architect stalls are detected and retried, not just coding agent stalls.

### 12. Test-Aware Stall Detection

- When a coding agent stall is detected (turn ended, no submit_pr called), before sending the continuation prompt the orchestrator must:
  - Run make test in the agent's worktree.
  - Capture the exit code and output.
- If tests fail, the continuation prompt must include:
  - The test failure output (truncated to a reasonable limit if very long).
  - A directive to fix the failing tests before submitting.
- If tests pass, the continuation prompt must still include:
  - A note that tests are passing.
  - A directive to continue working and submit the PR.
- Test-aware stall detection is specific to coding agents — manager and architect agents operate on the plan branch and do not have a meaningful `make test` gate. Review agents also skip this step.
- Acceptance criteria:
  - On coding agent stall, make test runs in the agent worktree before retry.
  - Test failure output is included in the continuation prompt when tests fail.
  - Test pass status is included in the continuation prompt when tests pass.
  - The existing stall detection behavior from section 11 is preserved — test-aware detection augments it, not replaces it.

## V2 Known Limitations

- Stall detection is per-turn only — it does not detect agents that are running but making no progress within a turn (addressed in v8, section 34).
- Test-aware stall detection runs make test only, not make integration-test.
- Manager and architect stall detection checks for output file creation, which may miss partial or malformed output — the orchestrator does not validate content quality at the stall detection level.

## V3 Features — Observability And Metrics

### 13. Tick Summary Line

- At the end of each orchestrator tick, the orchestrator must log a single INFO-level summary line capturing the full system state snapshot.
- The summary line must include:
  - `architect`: `no-op`, `updated`, or `skipped`
  - `manager`: `no-op`, `updated`, or `skipped`
  - `coding`: ticket ID + status (`running`, `stalled`, `submitted`, `failed`) + wall time, or `idle`
  - `merge`: `idle`, `processing`, or ticket ID being merged
  - `open` / `in-progress` / `done`: current ticket counts
- Example format:
  - `tick 42 summary: architect=no-op manager=no-op coding=0031(running, 3m12s) merge=idle open=2 in-progress=1 done=14`
- Acceptance criteria:
  - Every tick produces exactly one summary line at INFO level.
  - The line contains all specified fields.
  - Wall times are human-readable (e.g., `3m12s`).

### 14. Ticket Lifecycle Logging

- The orchestrator must log an INFO-level line for every ticket state transition, with timing.
- Required log points:
  - Assignment: `ticket <id>: open -> in-progress (assigned, worktree=<path>)`
  - Coding agent start: `ticket <id>: coding agent started (model=<model>, attempt <n>/<max>)`
  - Coding agent finish: `ticket <id>: coding agent finished (exit=<code>, wall=<duration>, stall=<bool>)`
  - PR submission: `ticket <id>: submit_pr called (summary="<summary>")`
  - Merge queue entry: `ticket <id>: merge queue entered (position=<n>)`
  - Merge start: `ticket <id>: merge started (make test running)`
  - Merge success: `ticket <id>: merge succeeded (test wall=<duration>)`
  - Merge failure: `ticket <id>: merge failed (reason=<reason>)`
  - Completion: `ticket <id>: in-progress -> done (total wall=<duration>, attempts=<n>)`
  - Reopen: `ticket <id>: in-progress -> open (reopened, reason=<reason>, attempts=<n>, total wall=<duration>)`
- For stall-related events:
  - Stall detection: `ticket <id>: coding agent stalled (attempt <n>/<max>, no submit_pr)`
  - Pre-retry test: `ticket <id>: make test before retry: <PASS|FAIL> (exit=<code>, wall=<duration>)`
  - Continuation: `ticket <id>: continuation prompt sent (attempt <n>/<max>, test_status=<passing|failing>)`
- Acceptance criteria:
  - All listed transitions produce the specified log lines at INFO level.
  - Log lines include ticket ID for correlation.
  - Durations are human-readable.

### 15. Per-Ticket Metrics In Agent Run Notes

- The orchestrator must capture structured metrics per ticket and persist them in the agent run notes on the plan branch.
- Required metrics fields:
  - `wall_time_seconds`: total elapsed time from assignment to done/reopen.
  - `coding_wall_seconds`: time spent in the coding agent (per attempt and total).
  - `test_wall_seconds`: time spent running make test (merge queue + stall checks).
  - `attempt_count`: number of coding agent attempts.
  - `outcome`: `done`, `reopened`, or `parked`.
  - `failure_reason`: `stall`, `test_failure`, `merge_conflict`, `timeout_hard`, `timeout_no_output`, or `parked` (only set when outcome is not `done`).
  - `model`: which model was used for the coding agent.
  - `stdout_bytes`: size of agent stdout in bytes (proxy for token usage).
- Metrics must be appended to the ticket markdown alongside existing agent run notes.
- Acceptance criteria:
  - Every completed or reopened ticket has structured metrics in its run notes.
  - All listed fields are present.
  - Timing values are in seconds for machine readability.

### 16. Session Summary On Shutdown

- When the orchestrator shuts down (signal or idle exit), it must log a session summary at INFO level.
- The summary must include:
  - Aggregate counts: `uptime`, `ticks`, `tickets_completed`, `tickets_reopened`, `tickets_parked`, `merge_queue_processed`.
  - Averages: `avg_ticket_wall`, `avg_coding_wall`, `avg_test_wall`.
  - `first_attempt_success`: percentage of done tickets that succeeded on their first coding agent attempt.
- Example format:
  - `session summary: uptime=1h23m ticks=47 tickets_completed=3 tickets_reopened=1 tickets_parked=0 merge_queue_processed=3`
  - `session summary: avg_ticket_wall=5m12s avg_coding_wall=4m02s avg_test_wall=38s first_attempt_success=75%`
- Acceptance criteria:
  - On shutdown, the orchestrator logs exactly two summary lines (counts and averages).
  - All listed fields are present.
  - If no tickets were completed, averages must show `n/a` or `0`.

### 17. Status Command Enhancement

- `scriptorium status` must be extended to show:
  - Elapsed time for the current in-progress ticket (how long it has been running).
  - The last N completed tickets (default 5) with outcome (`done`, `reopened`, `parked`) and wall time.
  - Cumulative first-attempt success rate across all done tickets.
- Acceptance criteria:
  - `scriptorium status` output includes in-progress ticket elapsed time.
  - `scriptorium status` output includes recent completed tickets with outcomes and timing.
  - `scriptorium status` output includes first-attempt success rate.
  - Existing status output (ticket counts, active ticket info) is preserved.

### 18. Ticket Difficulty Prediction

- Before a ticket is assigned to a coding agent, the orchestrator must run a prediction prompt to estimate difficulty and expected duration.
- The prediction must be generated by a lightweight agent call (using the configured coding agent model via codex harness).
- The prediction prompt must include:
  - The ticket content.
  - The relevant area content.
  - Current spec summary context.
- The prediction output must include:
  - `predicted_difficulty`: `trivial`, `easy`, `medium`, `hard`, or `complex`.
  - `predicted_duration_minutes`: estimated wall time in minutes.
  - `reasoning`: brief explanation of the prediction.
- The prediction must be:
  - Logged at INFO level: `ticket <id>: predicted difficulty=<level> duration=<n>min`.
  - Appended to the ticket markdown as a prediction section before coding begins.
- Acceptance criteria:
  - Every ticket gets a prediction before coding agent assignment.
  - The prediction is logged and persisted in the ticket markdown.
  - Prediction does not block or significantly delay ticket assignment (should be fast).

### 19. Ticket Post-Analysis

- After a ticket reaches `done` or is reopened/parked, the orchestrator must run a brief post-analysis.
- The post-analysis must compare predicted vs actual metrics:
  - Predicted difficulty vs actual attempt count and outcome.
  - Predicted duration vs actual wall time.
- The post-analysis output must include:
  - `actual_difficulty`: assessment based on actual metrics (`trivial`, `easy`, `medium`, `hard`, `complex`).
  - `prediction_accuracy`: whether the prediction was `accurate`, `underestimated`, or `overestimated`.
  - `brief_summary`: one-sentence summary of what happened.
- The post-analysis must be:
  - Logged at INFO level: `ticket <id>: post-analysis: predicted=<level> actual=<level> accuracy=<accuracy> wall=<duration>`.
  - Appended to the ticket markdown as a post-analysis section.
- Acceptance criteria:
  - Every completed, reopened, or parked ticket gets a post-analysis.
  - The post-analysis is logged and persisted in the ticket markdown.
  - Post-analysis compares prediction to actuals.

## V3 Known Limitations

- Ticket predictions use heuristic difficulty levels, not calibrated estimates — accuracy will improve over time as data accumulates.
- Post-analysis is a simple predicted-vs-actual comparison, not a detailed root-cause analysis.
- Dynamic routing based on predicted difficulty is out of scope — v3 collects the data, future versions may act on it.
- All metrics are stored in logs and plan-branch markdown only — no external dashboards or time-series storage.
- `stdout_bytes` is a rough proxy for token usage; real token counts require harness-level API integration.
- Session summary averages are per-session only, not cumulative across sessions.

## V3 Acceptance Criteria

- All v1 and v2 acceptance criteria remain.
- Tick summary lines appear in `scriptorium run` output at INFO level.
- Ticket lifecycle transitions are logged with timing at INFO level.
- Per-ticket metrics are persisted in agent run notes on the plan branch.
- Session shutdown produces aggregate summary lines.
- `scriptorium status` shows enhanced output with timing and success rates.
- Ticket predictions are generated and logged before coding begins.
- Ticket post-analysis is generated and logged after ticket completion.

## V4 Features — Merge Reviewing And Health Cache

### 20. Pre-Submit Test Gate

- The `submit_pr` MCP tool must run quality checks before accepting a submission.
- When a coding agent calls `submit_pr`, the MCP handler must:
  - Resolve the agent's worktree path from the active ticket assignment.
  - Run `make test` in the agent's worktree.
  - If tests fail: return an error response to the agent with the test failure output (truncated to a reasonable limit), directing the agent to fix the failing tests and call `submit_pr` again. The merge request must NOT be enqueued.
  - If tests pass: record the submit summary and return a success response. The merge request is enqueued as before.
- The test run must be logged: `ticket <id>: submit_pr pre-check: <PASS|FAIL> (exit=<code>, wall=<duration>)`.
- The agent remains running during the test execution — `submit_pr` blocks until tests complete, then returns the result to the agent.
- This replaces the previous behavior where `submit_pr` unconditionally accepted submissions.
- Acceptance criteria:
  - `submit_pr` runs `make test` before enqueuing.
  - If tests fail, the agent receives an error response with failure output and can retry.
  - If tests pass, the merge request is enqueued normally.
  - Test execution is logged with ticket ID, exit code, and wall time.

### 21. Review Agent

- After a coding agent successfully submits via `submit_pr` (tests passed, merge request enqueued), the orchestrator must run a review agent before merge queue processing.
- The review agent is a new agent role with its own configuration under `agents.reviewer` in `scriptorium.json`.
- Review agent configuration supports the same fields as other roles: `harness`, `model`, `reasoningEffort`.

#### Review Flow

- When the orchestrator processes a pending merge queue item, before running quality gates and merging, it must:
  1. Start a review agent session in the ticket's worktree.
  2. The review agent prompt must include:
     - The full ticket content (intent and requirements).
     - The diff of changes against `master` (via `git diff master...ticket-branch`).
     - The relevant area content.
     - The submit summary from the coding agent.
  3. The review agent has access to a `submit_review` MCP tool with two actions:
     - `approve`: accepts the changes, merge proceeds.
     - `request_changes`: rejects the changes with a `feedback` string explaining what needs to change.
  4. The review agent must call `submit_review` to signal its decision.

#### Review Outcomes

- **Approved:** The merge queue proceeds with its existing quality gate flow (merge master, run tests, fast-forward merge).
- **Changes requested:**
  - The pending merge queue item is removed.
  - The ticket remains in `tickets/in-progress/`.
  - A review feedback section is appended to the ticket markdown with the reviewer's feedback.
  - A new coding agent session is started with the original ticket content plus the review feedback, using the same worktree and branch.
  - The coding agent must call `submit_pr` again when done, which triggers the full flow again (pre-submit tests, then review).
  - Review-driven retries count toward the ticket's total attempt count.
- **Stall (review agent exits without calling `submit_review`):**
  - Treat as approval — the merge proceeds. This avoids blocking the pipeline on a reviewer stall.
  - Log a warning: `ticket <id>: review agent stalled, defaulting to approve`.

#### Review Lifecycle Logging

- Review start: `ticket <id>: review started (model=<model>)`.
- Review approved: `ticket <id>: review approved`.
- Review changes requested: `ticket <id>: review requested changes (feedback="<summary>")`.
- Review stall: `ticket <id>: review agent stalled, defaulting to approve`.

#### Review Agent Notes

- Review outcomes must be appended to the ticket markdown as structured review notes:
  - `**Review:** approved` or `**Review:** changes requested`.
  - `**Review Feedback:** <feedback text>` (when changes requested).
  - Backend, exit code, and wall time, consistent with existing agent run notes.

- Acceptance criteria:
  - Every merge queue item goes through review before merging.
  - The review agent receives the diff, ticket content, area context, and submit summary.
  - Approved reviews proceed to the existing merge queue quality gates.
  - Change requests restart the coding agent with review feedback.
  - Review outcomes are logged and persisted in ticket markdown.
  - Review stalls default to approval with a warning log.

### 22. Commit Health Cache

- The orchestrator must cache `master` health check results on the plan branch so they survive container restarts and session boundaries.
- Cache location: `health/cache.json` on the `scriptorium/plan` branch.
- Cache structure: a JSON object mapping commit hashes to result records:
  ```json
  {
    "<commit-hash>": {
      "healthy": true,
      "timestamp": "2026-03-12T14:30:00Z",
      "test_exit_code": 0,
      "integration_test_exit_code": 0,
      "test_wall_seconds": 42,
      "integration_test_wall_seconds": 18
    }
  }
  ```
- On startup or after a merge changes `master` HEAD, the orchestrator must:
  1. Look up the current `master` HEAD commit in `health/cache.json`.
  2. If found and healthy: skip the health check entirely, log `master health: cached healthy for <commit-hash>`.
  3. If found and unhealthy: skip the health check, mark master as unhealthy, log `master health: cached unhealthy for <commit-hash>`.
  4. If not found: run `make test` and `make integration-test` as before, then write the result to the cache and commit.
- Cache writes must be committed to the plan branch: `scriptorium: update health cache`.
- The existing in-memory `MasterHealthState` cache continues to work within a session — the plan-branch cache augments it for cross-session persistence.
- Cache entries are keyed by commit hash and naturally immutable — no invalidation is needed.
- Pruning: optional. The orchestrator may prune entries older than 30 days or keep the most recent N entries to prevent unbounded growth, but this is not required for v4.
- Acceptance criteria:
  - Health check results are persisted to `health/cache.json` on the plan branch.
  - On startup, cached healthy commits skip the full test suite.
  - On startup, cached unhealthy commits skip re-running tests and correctly report unhealthy.
  - Cache misses trigger the normal health check and write results to the cache.
  - Cache entries include commit hash, timestamp, exit codes, and wall times.

## V4 Known Limitations

- The review agent is a single-pass reviewer — it does not engage in back-and-forth dialogue with the coding agent.
- Review-driven change requests restart the coding agent from scratch rather than resuming the previous session.
- The review agent's stall-default-to-approve policy prioritizes throughput over review quality — future versions may retry the reviewer instead.
- Pre-submit test gate runs `make test` only, not `make integration-test` — integration tests remain a merge queue concern.
- Health cache pruning is optional and not enforced — cache files may grow over time in long-running projects.
- The `submit_pr` MCP handler blocks the coding agent process while tests run, which counts against the agent's hard timeout.

## V4 Acceptance Criteria

- All v1, v2, and v3 acceptance criteria remain.
- `submit_pr` runs `make test` before enqueuing and returns failure to the agent if tests fail.
- Every merge queue item is reviewed by a review agent before merging.
- Review approvals proceed to merge; change requests restart the coding agent with feedback.
- Review outcomes are logged and persisted in ticket markdown.
- `master` health check results are cached on the plan branch and survive restarts.
- Cached healthy commits skip redundant health checks on startup.

## V5 Features — Multi-Ticket Parallelism

### 23. Parallel Ticket Assignment

- The orchestrator must be able to assign multiple open tickets concurrently when they touch independent areas.
- Independence is determined by area: two tickets are independent if they reference different areas (via `**Area:** <area-id>`).
- Tickets that reference the same area must be serialized — only one ticket per area may be in-progress at a time.
- The orchestrator must assign up to N tickets per tick, where N is the configured concurrency limit.
- Assignment order remains oldest-first: the orchestrator scans open tickets in ID order and assigns each one whose area is not already occupied by an in-progress ticket.
- Each assigned ticket gets its own worktree and branch as before (`scriptorium/ticket-<id>`).
- The existing single-ticket assignment path (section 4) is replaced by the parallel assignment logic, but behavior is identical when concurrency is 1.

### 24. Concurrent Agent Execution

- The orchestrator must run multiple coding agent processes in parallel, one per assigned in-progress ticket.
- Each coding agent runs in its own worktree with its own branch, fully isolated from other agents.
- The orchestrator must track all running agent processes and their associated ticket state.
- Agent lifecycle (start, stall detection, continuation, submit_pr) applies independently to each running agent — the existing v2 stall detection and v4 pre-submit test gate operate per-agent.
- The orchestrator tick must not block on a single agent completing — it must:
  - Check for newly completable agents (exited processes).
  - Start new agents for newly assigned tickets.
  - Continue processing other tick phases (architect, manager, merge queue) while agents run.
- The concurrency limit is configurable via `scriptorium.json` under `concurrency.maxAgents` (integer, default 1).
  - A value of 1 preserves the existing serial behavior.
  - Recommended starting value for parallel operation is 2-3.
- The orchestrator must log when an agent slot opens or fills: `agent slots: <running>/<max> (ticket <id> started|finished)`.

### 25. Merge Queue Ordering With Parallel Agents

- Multiple coding agents may call `submit_pr` independently, resulting in multiple pending merge queue entries.
- Merge queue processing remains single-flight (section 7): the orchestrator processes at most one pending item per tick.
- Pending merge queue items are processed in submission order (FIFO by queue item ID).
- The existing review agent flow (section 21) applies to each merge queue item individually.
- If a merge fails (test failure, merge conflict), the ticket is reopened as before — this does not affect other in-flight agents or pending queue items.
- After a successful merge changes `master`, all other in-progress ticket worktrees must merge `master` into their branch before their next `submit_pr` pre-check or merge queue processing. This is handled by:
  - The merge queue already merges `master` into the ticket branch before running quality gates (section 7).
  - No additional synchronization is needed for running agents — they work against their branch and conflicts are caught at merge time.

### 26. Resource Management

- The orchestrator must monitor and respect API rate limits and token budgets across all parallel agents.
- Backpressure: when approaching rate limits, the orchestrator must delay new agent starts rather than failing running agents.
- The orchestrator must track aggregate `stdout_bytes` across all running agents as a proxy for token consumption.
- If a configurable token budget is set (`concurrency.tokenBudgetMB` in `scriptorium.json`, integer megabytes, optional), the orchestrator must:
  - Pause new ticket assignment when cumulative session `stdout_bytes` exceeds the budget.
  - Log a warning: `resource limit: token budget exhausted (<used>MB/<budget>MB), pausing new assignments`.
  - Allow running agents to complete normally.
- Rate limit detection: if an agent harness returns a rate-limit error (HTTP 429 or equivalent), the orchestrator must:
  - Log the event: `resource limit: rate limited (ticket <id>, backing off <n>s)`.
  - Apply exponential backoff before starting new agents (not before retrying the failed agent — the harness handles its own retries).
  - Reduce effective concurrency by 1 temporarily until the backoff period expires.

## V5 Known Limitations

- Conflict detection is area-level only — two tickets in different areas that happen to touch the same file will not be detected as conflicting until merge time.
- Speculative execution (starting tickets that might conflict) is out of scope — only clearly independent tickets are parallelized.
- Dynamic concurrency scaling based on v3 metrics is out of scope — the concurrency limit is static per session.
- Token budget tracking uses `stdout_bytes` as a rough proxy — real token counts require harness-level API integration (same limitation as v3).
- Rate limit detection depends on harness-specific error reporting — not all backends may surface 429s uniformly.
- The merge queue remains single-flight even with parallel agents — this serialization point may become a bottleneck at high concurrency.

## V5 Acceptance Criteria

- All v1, v2, v3, and v4 acceptance criteria remain.
- Multiple tickets can be assigned and worked concurrently when they touch independent areas.
- Tickets sharing an area are serialized — only one in-progress ticket per area.
- The concurrency limit is configurable and defaults to 1 (preserving serial behavior).
- Multiple coding agents run in parallel, each in its own worktree.
- Agent lifecycle (stall detection, pre-submit tests, review) operates independently per agent.
- The merge queue processes submissions in FIFO order, one at a time.
- Failed merges do not affect other in-flight agents.
- Token budget and rate limit backpressure prevent resource exhaustion.
- Orchestrator logs show agent slot utilization.

## V7 Features — Code Quality And Correctness

### 27. Orchestrator Module Split

- `orchestrator.nim` must be decomposed into focused modules, each covering a single responsibility.
- Target modules and their responsibilities:
  - `git_ops.nim`: gitRun, gitCheck, worktree add/remove/recover.
  - `lock_management.nim`: repo lock, stale PID detection, plan worktree lock.
  - `ticket_metadata.nim`: parse area/depends/worktree fields, ticket/area ID helpers, open/done listing.
  - `prompt_builders.nim`: all buildXxxPrompt procs, plan scope, prediction prompt.
  - `output_formatting.nim`: formatAgentRunNote, formatMetricsNote, formatDuration, truncation.
  - `ticket_analysis.nim`: prediction, post-analysis, difficulty classification.
  - `merge_queue.nim`: ensureMergeQueueInitialized, enqueueMergeRequest, processMergeQueue.
  - `coding_agent.nim`: executeAssignedTicket, agent thread pool, slot management.
  - `architect_agent.nim`: spec sync, area generation, architect should-run check.
  - `manager_agent.nim`: ticket generation from areas, batch prompt.
  - `ticket_assignment.nim`: assignOldestOpenTicket, dependency check, worktree cleanup.
  - `health_checks.nim`: master health, health cache, state invariant validation.
  - `mcp_server.nim`: createOrchestratorServer, submit_pr/submit_review handlers, shared buffers.
  - `shared_state.nim`: locks init, token budget, rate limiting, session stats.
  - `interactive_sessions.nim`: interactive plan/ask sessions, input helpers.
  - `orchestrator.nim` (remaining): main loop, signal handlers, runOrchestrator entry points.
- Extraction order must be bottom-up: start with modules that have no internal dependencies (`git_ops`, `lock_management`, `ticket_metadata`), then work upward through modules that depend on already-extracted code.
- Each extraction must be a single commit that moves procs and updates imports.
- All existing tests (`make test`, `make integration-test`) must pass after each extraction — no behavior changes are permitted during extraction.
- Focused unit tests should be added for newly isolated modules where coverage is thin.
- Acceptance criteria:
  - Each target module exists as a separate `.nim` file under `src/`.
  - `orchestrator.nim` retains only the main loop, signal handlers, and top-level entry points.
  - Every intermediate commit (one per module extraction) passes `make test`.
  - No behavioral changes — only code movement and import updates.

### 28. SIGSEGV Shutdown Fix

- The orchestrator must shut down cleanly without triggering SIGSEGV in mummy's allocator.
- Root cause: calling `httpServer.close()` from the main thread while mummy's `serve()` is still running on the server thread causes a use-after-free in `addToSharedFreeList` during `destroy`.
- Fix approach: coordinate shutdown so the server thread closes itself rather than receiving a cross-thread close.
  - The main thread must set a shutdown flag (atomic or shared-memory signal).
  - The server thread must check the shutdown flag and call `close()` on itself.
  - The main thread must `joinThread()` only after the server thread has exited.
- The fix must not introduce a sleep-based workaround — shutdown must be event-driven.
- If mummy does not support flag-based shutdown, investigate:
  - Whether a newer mummy version fixes cross-thread `close()`.
  - Whether an alternative HTTP server library is needed.
- Acceptance criteria:
  - `scriptorium run` exits cleanly after signal or idle shutdown with exit code 0.
  - No SIGSEGV or illegal storage access on shutdown.
  - The MCP HTTP server thread terminates before the main thread exits.
  - Existing MCP tool functionality (submit_pr, submit_review) is unaffected.

### 29. Ticket Dependency Cycle Detection

- The orchestrator must detect and surface circular dependencies among tickets.
- At ticket creation time (manager agent):
  - After the manager writes new tickets, the orchestrator must validate that the dependency graph remains acyclic.
  - Build a directed graph from all open and in-progress tickets using `**Depends:** <id-list>` fields.
  - Check for strongly connected components (cycles) using a standard algorithm (Tarjan's or DFS-based).
  - If a cycle is detected, log an error: `ticket <id>: dependency cycle detected (<id> -> <id> -> ... -> <id>)`.
- Periodic scan during the orchestrator main loop:
  - On each tick (or at a configurable interval), scan all open tickets for dependency cycles.
  - Tickets that can never be assigned due to circular dependencies must be logged as warnings: `ticket <id>: permanently blocked by dependency cycle`.
- `scriptorium status` enhancement:
  - When blocked tickets exist, `status` must report them with the reason: `Blocked: <id> (circular dependency with <id-list>)`.
  - When tickets are blocked by unsatisfied (but non-circular) dependencies, `status` must report: `Waiting: <id> (depends on <id-list>)`.
- Acceptance criteria:
  - Circular dependencies are detected at ticket creation time and logged as errors.
  - Periodic scans identify tickets permanently blocked by cycles.
  - `scriptorium status` surfaces blocked and waiting tickets with explanations.
  - Non-circular dependency checking (`dependenciesSatisfied`) continues to work as before.
  - Unit tests cover: simple cycle (A->B->A), multi-node cycle (A->B->C->A), no cycle, self-dependency.

### 30. Review Agent Test Coverage

- The review agent must have comprehensive unit and integration test coverage beyond the existing noop-runner integration tests.
- Required unit tests for `buildReviewAgentPrompt`:
  - Verify the rendered prompt contains the expected sections: diff, ticket content, area context, and submit summary.
  - Verify each section is labeled and delimited so the review agent can parse them.
  - Verify the prompt includes the review instructions and available MCP tool description.
- Edge case tests for diff generation:
  - Empty diff: when `git diff master...ticket-branch` produces no output, the prompt must include a note that no changes were found and the review agent should flag this.
  - Failed diff: when the diff command fails (e.g., branch does not exist, force-pushed), the review flow must handle the error gracefully — log a warning and default to approval rather than crashing.
- Feedback truncation test:
  - When review feedback exceeds `ReviewFeedbackMaxBytes` (4096 bytes), it must be truncated to fit.
  - The truncated feedback must end with a truncation marker (e.g., `... [truncated]`).
  - A unit test must exercise the truncation boundary: feedback of exactly 4096 bytes, 4097 bytes, and well under 4096 bytes.
- Live integration test:
  - An integration test must run the review agent with a real model (similar to existing `integration_mcp_submit_pr_live.nim`).
  - The test must verify the review agent calls `submit_review` with either `approve` or `request_changes`.
  - The test must use a real diff against a real branch, not synthetic input.
- Acceptance criteria:
  - `buildReviewAgentPrompt` output structure is verified by unit tests.
  - Empty and failed diff edge cases are covered by unit tests.
  - Feedback truncation at `ReviewFeedbackMaxBytes` boundary is covered by a unit test.
  - A live integration test exercises the full review agent flow with a real model.
  - All new tests pass in `make test` (unit) and `make integration-test` (live).

## V7 Known Limitations

- The orchestrator module split is a refactoring-only change — no new functionality is added, and the public API surface of `orchestrator.nim` is preserved through re-exports.
- The SIGSEGV fix depends on mummy's threading model — if mummy fundamentally cannot support coordinated shutdown, a server library change may be required.
- Cycle detection uses a simple graph algorithm and does not handle dynamic dependency changes during a tick — dependencies are snapshot at scan time.
- Review agent live integration tests require API credentials and a running model, so they only run in `make integration-test`, not `make test`.

## V7 Acceptance Criteria

- All v1, v2, v3, v4, and v5 acceptance criteria remain.
- `orchestrator.nim` is decomposed into the specified modules with one commit per extraction, all tests passing after each.
- The orchestrator shuts down cleanly without SIGSEGV.
- Circular ticket dependencies are detected at creation time and surfaced in `scriptorium status`.
- Review agent has unit tests for prompt structure, diff edge cases, and feedback truncation, plus a live integration test.

## V8 Features — Crash Recovery And Deployment Reproducibility

### 31. Startup Recovery Sequence

- On orchestrator start, before entering the main polling loop, the orchestrator must run a `recoverFromCrash` procedure that detects and reconciles stale state from a previous crash or unclean shutdown.
- The recovery sequence must execute the following steps in order:

#### Step 1: Clean Orphaned Worktrees

- Call `cleanupStaleTicketWorktrees(repoPath)` to prune worktrees under `/tmp/scriptorium/` that do not correspond to any in-progress ticket.
- Remove git worktree locks held by dead processes: for each worktree with a lock file, check if the holding PID is still alive. If the PID is dead, remove the lock file and prune the worktree.
- If a PID is alive but not a known scriptorium process, log a warning: `recovery: worktree <path> locked by unknown process <pid>, skipping`.
- Log each cleaned worktree: `recovery: cleaned orphaned worktree <path>`.

#### Step 2: Detect Stale Agent Processes

- Scan `/tmp/scriptorium-*/` worktree directories for lock files or PID markers left by previous agent processes (`codex`, `claude` CLI processes).
- For each marker, check if the referenced PID is still alive.
- If the PID is dead, clean up the marker and log: `recovery: cleared stale agent marker for PID <pid>`.
- If the PID is alive, log a warning: `recovery: stale agent process <pid> still running in <worktree>, manual intervention may be needed`.
- The orchestrator must not kill orphaned agent processes automatically — it must log warnings and let the operator decide. Automatic process killing is out of scope for v8.

#### Step 3: Reconcile Dirty Plan Branch

- Open the plan worktree and check for uncommitted changes (`git status --porcelain`).
- If the working tree is clean, skip this step.
- If uncommitted changes are detected:
  - Check for the presence of a transition journal file (see section 32). If a journal exists, delegate to the journal replay/rollback logic.
  - If no journal exists, commit all uncommitted changes with message `scriptorium: recovery commit (unclean shutdown)` and log: `recovery: committed dirty plan branch state`.
- Log the recovery action taken: `recovery: plan branch reconciled (<action>)` where action is `clean`, `journal-replayed`, `journal-rolled-back`, or `committed`.

#### Step 4: Validate Merge Queue Vs Master HEAD

- For each pending item in `queue/merge/pending/`, resolve the ticket's branch and check whether it is already merged into `master` (via `git merge-base --is-ancestor`).
- If the ticket branch is already merged into `master` but the plan branch still shows the ticket as in-progress:
  - Move the ticket from `tickets/in-progress/` to `tickets/done/`.
  - Remove the pending merge queue entry.
  - Clear `queue/merge/active.md` if it references this ticket.
  - Commit with message `scriptorium: recovery — completed already-merged ticket <id>`.
  - Log: `recovery: ticket <id> already merged to master, completed on plan branch`.
- If `queue/merge/active.md` references a ticket that is no longer in-progress or whose branch does not exist, clear the active marker and log: `recovery: cleared stale active merge marker`.

#### Step 5: Log Recovery Summary

- After all recovery steps complete, log a single INFO-level summary: `recovery: cleaned <n> worktrees, cleared <m> stale markers, reconciled plan branch (<action>), completed <k> already-merged tickets`.
- If no recovery actions were needed, log: `recovery: clean startup, no recovery needed`.

- Acceptance criteria:
  - `recoverFromCrash` runs before the first orchestrator tick.
  - Orphaned worktrees from a previous run are cleaned up on startup.
  - Git worktree locks held by dead PIDs are removed.
  - Uncommitted plan branch changes are committed or reconciled via journal replay.
  - Merge queue entries for already-merged tickets are completed on the plan branch.
  - A recovery summary is logged at INFO level on every startup.

### 32. Atomic Plan Branch Transitions

- Multi-step plan branch operations (file content update, file move, queue cleanup, git commit) must be wrapped in a write-ahead journal to enable crash recovery.
- Journal file location: `.scriptorium-journal.json` in the plan worktree root.

#### Journal Structure

- The journal is a JSON file recording the intended transition before any filesystem operations begin:
  ```json
  {
    "operation": "ticket-transition",
    "timestamp": "2026-03-14T10:30:00Z",
    "steps": [
      {"action": "write", "path": "tickets/in-progress/0042.md", "content_hash": "<sha1>"},
      {"action": "move", "source": "tickets/in-progress/0042.md", "dest": "tickets/done/0042.md"},
      {"action": "remove", "path": "queue/merge/pending/0042.md"},
      {"action": "write", "path": "queue/merge/active.md", "content": ""}
    ],
    "commit_message": "scriptorium: complete ticket 0042"
  }
  ```

#### Write-Ahead Protocol

- Before executing any filesystem operations for a plan branch transition, the orchestrator must:
  1. Write the journal file describing all intended steps.
  2. `git add` and commit the journal file with message `scriptorium: begin transition — <operation>`.
  3. Execute the filesystem operations (writes, moves, removes) as described in the journal.
  4. `git add -A` and commit all changes with the transition's commit message.
  5. Remove the journal file and commit with message `scriptorium: complete transition`.
- If the process crashes at any point, the journal file's presence on the plan branch signals an incomplete transition.

#### Crash Recovery Replay

- During startup recovery (section 31, step 3), if a journal file is found:
  - Read the journal and inspect the current filesystem state.
  - For each step in the journal, check whether it has already been applied:
    - `write`: check if the file exists with the expected content hash.
    - `move`: check if the destination exists and the source does not.
    - `remove`: check if the file no longer exists.
  - If all steps are applied: commit any uncommitted changes and remove the journal (complete the transition).
  - If some steps are applied and some are not: replay the remaining steps, then commit and remove the journal.
  - If no steps are applied: roll back by removing any partial changes (`git checkout -- .` for unstaged changes), remove the journal, and commit. Log: `recovery: rolled back incomplete transition`.
- The replay/rollback decision must be deterministic based on filesystem state — no human intervention required.

- Acceptance criteria:
  - All ticket state transitions (open->in-progress, in-progress->done, in-progress->open) use the write-ahead journal.
  - Merge queue operations (enqueue, dequeue, clear active) use the write-ahead journal.
  - A crash at any point during a transition is recoverable on next startup.
  - Journal replay completes partial transitions correctly.
  - Journal rollback reverts incomplete transitions cleanly.
  - The journal file is removed after successful completion.
  - No journal file persists across a clean orchestrator run.

### 33. Docker Image Reproducibility

- The Dockerfile must pin all external dependencies to specific versions for build reproducibility.

#### Base Image Pinning

- The base image must be pinned to a specific tag rather than `:latest`:
  ```dockerfile
  FROM gitea.solution-nine.monofuel.dev/monolab/monolab-nim:2.2.4
  ```
- Optionally, the image may also be pinned by digest (`@sha256:...`) for immutable builds, but tag pinning is the minimum requirement.

#### NPM Package Version Pinning

- The `@openai/codex` and `@anthropic-ai/claude-code` npm packages must be installed with explicit version specifiers:
  ```dockerfile
  RUN npm install --global @openai/codex@<version> @anthropic-ai/claude-code@<version>
  ```
- The exact versions to pin are the current latest stable versions at the time of implementation.

#### Version Traceability

- The Docker entrypoint or a startup log line must print the installed versions of pinned dependencies for traceability:
  - Base image tag (from a build arg or label).
  - `codex --version` output.
  - `claude --version` output.
- This allows operators to confirm which versions are running in a given container.

#### Update Mechanism

- A Makefile target (`make check-updates` or similar) should check for available updates to pinned npm packages and report whether newer versions exist.
- This target is advisory only — it does not automatically update the Dockerfile.

- Acceptance criteria:
  - The Dockerfile does not use `:latest` for the base image.
  - The Dockerfile specifies explicit versions for `@openai/codex` and `@anthropic-ai/claude-code`.
  - Builds on different days with the same Dockerfile produce the same dependency versions.
  - Installed dependency versions are logged on container startup.

### 34. Agent Crash Recovery

- The orchestrator must improve its handling of agent process crashes and hangs beyond the existing no-output and hard timeout mechanisms.

#### Progress-Based Stall Detection

- In addition to the existing no-output timeout (which triggers when the agent produces no stdout for a configured interval), the orchestrator must implement progress-based stall detection for all agent roles.
- "Progress" is defined as the agent calling an MCP tool or producing a tool-call stream event within a configurable window (`agents.<role>.progressTimeout` in `scriptorium.json`, default 10 minutes).
- Progress-based stall detection applies to all agent roles (coding, manager, architect, review), consistent with the universal stall detection policy in section 11.
- If the agent produces stdout output (e.g., reasoning tokens, status messages) but makes no tool calls within the progress timeout window, the orchestrator must treat this as a stall.
- On progress-based stall detection:
  - Log: `<role> <id>: agent stalled — output active but no tool calls for <duration>`.
  - Terminate the agent process.
  - Proceed with the existing stall continuation flow (section 11): for coding agents, run pre-retry tests (section 12) then send continuation prompt; for other roles, send the role-appropriate continuation prompt directly.
- The no-output timeout and hard timeout remain as independent safety nets — progress-based detection is an additional layer.
- Progress tracking must use the existing `AgentEventHandler` callback: tool-type events reset the progress timer, other event types do not.

#### Worktree Health Check Before Retry

- Before starting a retry attempt (whether triggered by stall detection, progress timeout, or agent crash), the orchestrator must validate the worktree's health.
- Health check steps:
  1. Run `git status --porcelain` in the worktree. If it fails, the worktree is corrupt.
  2. Run `git diff --stat` to assess uncommitted changes.
  3. If the worktree is corrupt (git commands fail):
     - Remove and recreate the worktree from the ticket branch: `git worktree remove --force <path>` followed by `git worktree add <path> <branch>`.
     - Log: `ticket <id>: worktree corrupt, recreated from branch`.
  4. If the worktree has uncommitted changes:
     - Commit them with message `scriptorium: save partial agent work (attempt <n>)` on the ticket branch.
     - Log: `ticket <id>: saved uncommitted agent work before retry`.
  5. If the worktree is clean, proceed normally.
- The retry agent receives the worktree in a known-good state with all prior work committed to the branch.

#### Detect Committed-But-Not-Submitted Work

- At the start of each coding agent attempt (including the first attempt), the orchestrator must check whether the ticket branch already has commits ahead of `master` that were not submitted via `submit_pr`.
- Detection: compare the ticket branch HEAD against `master` using `git log master..<branch> --oneline`. If commits exist, prior work is present.
- When committed-but-not-submitted work is detected:
  - Log: `ticket <id>: found <n> committed changes from prior attempt, agent will continue from branch tip`.
  - Include a note in the agent prompt: inform the agent that prior work exists on the branch and it should review existing changes before proceeding.
  - Do not reset the branch — the agent works from the branch tip, building on prior commits.
- This handles the crash window where an agent committed work to the branch but crashed before calling `submit_pr`.

- Acceptance criteria:
  - Progress-based stall detection terminates agents that produce output but make no tool calls within the configured window.
  - The progress timeout is configurable and defaults to 10 minutes.
  - Worktree health is validated before every retry attempt.
  - Corrupt worktrees are recreated from the branch automatically.
  - Uncommitted agent work is saved to the branch before retry.
  - Committed-but-not-submitted work is detected and surfaced in the agent prompt.
  - Existing no-output timeout and hard timeout behavior is preserved.

## V8 Known Limitations

- The orchestrator does not automatically kill orphaned agent processes — operators must handle this manually. Automatic process killing risks terminating legitimate processes.
- Progress-based stall detection relies on tool-call events from the harness stream. If a harness does not emit tool events (e.g., a future backend), the progress timeout will not function and the no-output timeout remains the only stall detector.
- Write-ahead journal adds two extra commits per transition (journal write and journal removal). This increases plan branch commit volume but ensures recoverability.
- Docker version pinning requires manual updates when new versions are released — the `make check-updates` target is advisory only.
- Worktree health checks add latency before each retry attempt due to git status and diff operations.
- Committed-but-not-submitted detection depends on `master` as the comparison base — if `master` has advanced significantly, the diff may be large.

## V8 Acceptance Criteria

- All v1, v2, v3, v4, v5, and v7 acceptance criteria remain.
- The orchestrator runs a startup recovery sequence before the first tick.
- Orphaned worktrees and stale locks are cleaned up on startup.
- Dirty plan branch state is reconciled via journal replay or committed on startup.
- Merge queue entries for already-merged tickets are completed automatically on startup.
- All plan branch transitions use a write-ahead journal for crash safety.
- Journal-based recovery replays or rolls back incomplete transitions deterministically.
- The Dockerfile pins the base image tag and npm package versions.
- Installed dependency versions are logged on container startup.
- Progress-based stall detection catches agents that output but make no tool calls.
- Worktree health is validated and repaired before agent retries.
- Committed-but-not-submitted work is detected and communicated to retry agents.

## V11 Features — Fresh Project Onboarding

### 35. Project Opinions

- Scriptorium is opinionated about managed project structure. These opinions are rigid and apply to all managed Nim projects.
- Language and dependency management:
  - Nim is the implementation language.
  - nimby is the dependency manager (`nimby.lock` for pinned deps, `nimby sync`).
  - A `.nimble` file provides package metadata and versioning.
- Required project structure:
  - `src/` for source code.
  - `tests/` for all test files (unit, integration, e2e).
  - `Makefile` at repo root with required targets.
  - `AGENTS.md` at repo root for coding agent instructions.
  - `scriptorium.json` at repo root for orchestrator configuration.
  - `docs/` for project documentation and version plans.
- Make targets (quality gates):
  - `make build` — compile the project. Must exit 0 on success. Run before tests.
  - `make test` — unit tests. Must be fast, require no network access, and no API keys. Run on every commit and before every merge. Failure is a hard gate.
  - `make integration-test` — tests that hit real services. May require credentials. Run on default branch pushes. Failure reopens the ticket.
  - `make e2e-test` — (optional) full end-to-end smoke tests. Run on default branch pushes if present. Failure reopens the ticket.

### 36. Default Branch Detection

- The orchestrator must not hardcode `master` or `main`. Instead it must resolve the default branch dynamically.
- Resolution order:
  1. Check `refs/remotes/origin/HEAD` — if set, use that.
  2. If not set, probe for common names (`master`, `main`, `develop`) and use whichever exists locally.
  3. During `scriptorium init`, once resolved, run `git remote set-head origin <branch>` so future runs skip the probe.
  4. If nothing works, error with a clear message asking the user to set the default branch.
- All hardcoded `master` references in the orchestrator, merge queue, and init code must be replaced with the resolved default branch.
- A unit test must cover the resolution logic.
- Acceptance criteria:
  - The orchestrator resolves the default branch dynamically on startup.
  - `scriptorium init` sets `origin/HEAD` after resolving the default branch.
  - No hardcoded `master` or `main` strings remain in orchestrator, merge queue, or init code paths.
  - Projects using `main` or other branch names work without additional configuration.

### 37. CLI Init Subcommand

- The init command must change from `scriptorium --init` flag syntax to `scriptorium init` subcommand syntax, consistent with all other commands (`run`, `plan`, `ask`, `status`, `worktrees`).
- `scriptorium init [path]` is the new syntax.
- `--init` may be kept as a deprecated alias or dropped — there are no external users yet.
- CLI help and documentation must be updated to reflect the new syntax.
- Acceptance criteria:
  - `scriptorium init` and `scriptorium init <path>` work as the primary init interface.
  - CLI help lists `init` as a subcommand alongside `run`, `plan`, `ask`, `status`, `worktrees`.

### 38. Init Generates AGENTS.md

- On `scriptorium init`, if `AGENTS.md` does not already exist on the default branch, copy `agents_example.md` to `AGENTS.md` and commit it.
- The example file is a generic Nim template covering style, imports, error handling, and testing conventions.
- If `AGENTS.md` already exists, skip this step — do not overwrite user work.
- Print a note: `Created AGENTS.md — edit to match your project conventions.`
- Acceptance criteria:
  - `scriptorium init` creates `AGENTS.md` on the default branch when it does not exist.
  - Existing `AGENTS.md` is not overwritten.
  - The generated file is committed to the default branch.

### 39. Init Generates Starter Makefile

- On `scriptorium init`, if no Makefile exists on the default branch, generate a minimal one with placeholder targets:
  ```makefile
  test:
  	@echo "no tests yet"

  integration-test:
  	@echo "no integration tests yet"

  e2e-test:
  	@echo "no e2e tests yet"
  ```
- Commit it on the default branch.
- If a Makefile already exists, skip — do not overwrite.
- Print a note: `Created Makefile with placeholder targets — replace with real build commands.`
- The placeholder targets exit 0 so the orchestrator can run immediately.
- Acceptance criteria:
  - `scriptorium init` creates a Makefile with placeholder `test`, `integration-test`, and `e2e-test` targets when none exists.
  - Existing Makefiles are not overwritten.
  - The generated Makefile is committed to the default branch.

### 40. Init Generates Starter scriptorium.json

- On `scriptorium init`, if no `scriptorium.json` exists, generate one using `defaultConfig()` and write it to the repo root.
- Do not commit it — it may contain user-specific preferences and should be gitignored or committed at the user's discretion.
- Print a note: `Created scriptorium.json — configure agent models and harnesses.`
- Acceptance criteria:
  - `scriptorium init` creates `scriptorium.json` when it does not exist.
  - The file is written but not committed.
  - Existing `scriptorium.json` is not overwritten.

### 41. Pre-Flight Validation In `scriptorium run`

- Before launching the orchestrator polling loop, `scriptorium run` must perform upfront validation checks with clear, actionable error messages.
- Required checks:
  - `scriptorium/plan` branch exists (already done).
  - `AGENTS.md` exists on the default branch. Warn if missing.
  - Makefile exists on the default branch. Error if missing — the orchestrator cannot function without quality gates.
  - `make test` and `make integration-test` targets exist (verify via `make -n test` and `make -n integration-test` dry-run). Warn if either fails.
  - Agent binary is available (`codex`, `claude`, or `typoi` depending on configured harness). Error if missing.
  - Agent auth is available (API keys or OAuth credentials for the configured harness). Error if missing.
- Error messages must be clear and actionable, e.g.:
  - `Error: Makefile not found. Run 'scriptorium init' or create a Makefile with 'test' and 'integration-test' targets.`
- Acceptance criteria:
  - Missing Makefile or agent binary causes `scriptorium run` to exit with an error before polling starts.
  - Missing `AGENTS.md` produces a warning but does not block startup.
  - Missing make targets produce warnings.
  - Missing agent auth produces an error.
  - All error messages suggest corrective action.

### 42. Improved Post-Init Guidance

- After `scriptorium init` completes, the output must provide comprehensive setup guidance listing all created artifacts and next steps.
- Output format:
  ```
  Initialized scriptorium workspace.

  Created:
    AGENTS.md           — project conventions for coding agents (edit to fit)
    Makefile            — placeholder test targets (replace with real commands)
    scriptorium.json    — agent configuration (set your models and API keys)
    scriptorium/plan    — plan branch with spec, areas, and tickets

  Next steps:
    1. Edit scriptorium.json to configure your agent models and harnesses
    2. Edit AGENTS.md to describe your project conventions
    3. Run `scriptorium plan` to build your spec with the Architect
    4. Run `scriptorium run` to start the orchestrator
  ```
- Only list artifacts that were actually created (skip items that already existed).
- Acceptance criteria:
  - Post-init output lists all created artifacts with descriptions.
  - Post-init output includes numbered next steps.
  - Artifacts that were skipped (already existed) are not listed in the "Created" section.

### 43. Updated Spec Placeholder

- The spec placeholder created by `scriptorium init` must be updated to indicate this is a new project:
  ```
  # Spec

  This is a new project. See AGENTS.md for project conventions.

  Run `scriptorium plan` to build your spec with the Architect.
  ```
- This replaces the current placeholder which does not reference `AGENTS.md`.
- Acceptance criteria:
  - New projects initialized with `scriptorium init` get the updated spec placeholder.
  - The placeholder references `AGENTS.md`.

### 44. E2E Test Uses `scriptorium init`

- The existing e2e test (Euler test) must be updated to use `scriptorium init` instead of manually seeding `AGENTS.md` and `Makefile`.
- Changes:
  - Remove manual `AGENTS.md` and Makefile creation from test setup.
  - Run `scriptorium init` (programmatically via `runInit`) on the temp repo.
  - Verify `AGENTS.md`, Makefile, and `scriptorium.json` were created by init.
  - Continue with the existing flow: write spec, start orchestrator, verify ticket completion and `make test` passing.
- This proves init produces a repo the orchestrator can run against without any manual scaffolding.
- Acceptance criteria:
  - The e2e test uses `scriptorium init` for repo setup instead of manual file creation.
  - The test verifies that init-created artifacts are sufficient for orchestrator operation.
  - The existing test flow (spec, orchestrator, ticket completion) continues to pass.

## V11 Known Limitations

- Project opinions are Nim-only — support for other languages is out of scope.
- The starter Makefile contains placeholder targets that exit 0 — real build and test commands must be added by the user or via tickets.
- `scriptorium.json` is not committed by init — users must decide whether to commit or gitignore it.
- Default branch detection relies on `refs/remotes/origin/HEAD` or probing common names — unusual branch naming conventions may require manual `git remote set-head` setup.
- Pre-flight validation checks for agent auth are best-effort — some auth mechanisms (OAuth tokens, environment-specific credentials) may not be detectable at startup.
- The `agents_example.md` template is generic Nim guidance — users must customize it for their specific project conventions.

## V11 Acceptance Criteria

- All v1, v2, v3, v4, v5, v7, and v8 acceptance criteria remain.
- `scriptorium init` is a subcommand (not `--init` flag).
- `scriptorium init` generates `AGENTS.md`, a starter Makefile, and `scriptorium.json` on fresh repos.
- Existing files are never overwritten by init.
- The default branch is resolved dynamically — no hardcoded `master` or `main`.
- `scriptorium run` performs pre-flight validation with clear error messages before polling.
- Post-init output provides comprehensive setup guidance.
- The spec placeholder references `AGENTS.md` for new projects.
- The e2e test uses `scriptorium init` and proves a fresh repo can run without manual scaffolding.

## V12 Features — Chat Bot Integrations

### 45. Discord Bot (Current State)

- `scriptorium discord` runs a Discord bot that acts as a frontend to the Architect.
- The bot uses the `guildy` library for Discord gateway connections.
- Chat modes are selected by message prefix:
  - `plan:` — planning mode, can modify `spec.md` and create tickets on the plan branch (default when no prefix).
  - `ask:` — read-only Q&A with the Architect, no plan branch writes.
  - `do:` — full repo access mode for ad-hoc coding tasks.
- Slash commands (no LLM calls, read/write orchestrator state directly):
  - `/status` — ticket counts, active agents, in-progress elapsed times, blocked/waiting tickets, pause state.
  - `/queue` — merge queue contents and ticket lists.
  - `/pause` — write a pause flag; orchestrator stops picking up new work.
  - `/resume` — remove the pause flag.
- Configuration in `scriptorium.json` under `discord`:
  - `enabled`: boolean.
  - `serverId`: Discord guild ID for guild-scoped slash command registration.
  - `channelId`: scopes the bot to a single channel.
  - `allowedUserIds`: list of Discord user IDs; messages from others are ignored.
- `DISCORD_TOKEN` environment variable is required; never stored in config.
- Each chat message spawns a background thread to avoid blocking the gateway event loop.
- Responses are truncated to 2000 characters (Discord limit).
- The bot is a standalone process — the orchestrator does not know about Discord.

### 46. Mattermost Bot

- `scriptorium mattermost` runs a Mattermost bot that acts as a frontend to the Architect, mirroring the Discord bot's functionality.
- The bot uses the `mosty` library (`monofuel/mosty`) for Mattermost WebSocket gateway connections and REST API.

#### Chat Modes

- Chat modes are identical to the Discord bot, selected by message prefix:
  - `plan:` — planning mode, can modify `spec.md` and create tickets (default when no prefix).
  - `ask:` — read-only Q&A with the Architect, no plan branch writes.
  - `do:` — full repo access mode for ad-hoc coding tasks.
- The existing `parseChatMode` proc must be reused (it is transport-agnostic).

#### Slash Commands

- The Mattermost bot must support the same slash commands as the Discord bot:
  - `/status` — ticket counts, active agents, in-progress elapsed times, blocked/waiting tickets, pause state.
  - `/queue` — merge queue contents and ticket lists.
  - `/pause` — write a pause flag.
  - `/resume` — remove the pause flag.
- Mattermost slash commands are registered as custom slash commands on the Mattermost server, or the bot detects `/command` messages in the channel and responds inline.
- The bot must detect messages starting with `/status`, `/queue`, `/pause`, or `/resume` and handle them directly without invoking the Architect.

#### Message Handling

- The bot connects to the Mattermost WebSocket gateway via `mosty.startGateway`.
- Incoming posts are filtered by:
  - Channel ID (must match configured `channelId`).
  - Allowed user IDs (messages from other users are ignored).
  - Bot's own messages are ignored (prevent self-reply loops).
- Each chat message spawns a background thread to avoid blocking the gateway event loop.
- Responses are posted back to the channel via `mosty.createPost`.
- Mattermost has a 16383 character post limit; responses must be truncated to fit.

#### Configuration

- Configuration in `scriptorium.json` under `mattermost`:
  ```json
  {
    "mattermost": {
      "enabled": false,
      "url": "",
      "channelId": "",
      "allowedUserIds": []
    }
  }
  ```
  - `enabled`: boolean.
  - `url`: Mattermost server base URL (e.g., `https://mattermost.example.com`).
  - `channelId`: scopes the bot to a single channel.
  - `allowedUserIds`: list of Mattermost user IDs; messages from others are ignored.
- `MATTERMOST_TOKEN` environment variable provides the bot access token; never stored in config.

#### Implementation Structure

- Source file: `src/scriptorium/mattermost_bot.nim`.
- The module must follow the same structure as `discord_bot.nim`:
  - Reuse `parseChatMode` from `discord_bot.nim` (or extract to a shared chat module).
  - Reuse `handleChatMessage`, `handleAskMessage`, `handleDoMessage` logic — the core Architect invocation is transport-agnostic.
  - Reuse `formatStatusMessage`, `formatQueueMessage`, `handlePause`, `handleResume` for slash command responses.
- Shared chat logic (mode parsing, status/queue formatting, pause/resume handlers) should be extracted to a `chat_common.nim` module that both `discord_bot.nim` and `mattermost_bot.nim` import.
- The `runMattermostBot` proc is the entry point, called from `cmdMattermost` in `scriptorium.nim`.

#### Docker Support

- A `mattermost` service must be added to `docker-compose.yml`, mirroring the `discord` service structure.
- The service must mount the workspace and credentials, load `.env` for `MATTERMOST_TOKEN`, and run `entrypoint.sh mattermost`.

#### Environment File

- `.env.example` must include `MATTERMOST_TOKEN=` alongside the existing `DISCORD_TOKEN=`.

- Acceptance criteria:
  - `scriptorium mattermost` starts a gateway connection to the configured Mattermost server.
  - Chat messages from allowed users invoke the Architect in the correct mode (plan/ask/do).
  - Slash commands (`/status`, `/queue`, `/pause`, `/resume`) return orchestrator state without LLM calls.
  - Responses are posted to the configured channel and truncated to 16383 characters.
  - The bot ignores messages from non-allowed users, other channels, and its own posts.
  - Shared chat logic is extracted so Discord and Mattermost bots share mode parsing, status formatting, and pause/resume handlers.
  - Configuration is in `scriptorium.json` under `mattermost` with `url`, `channelId`, `allowedUserIds`.
  - `MATTERMOST_TOKEN` is read from the environment.
  - Docker compose includes a `mattermost` service.

## V12 Known Limitations

- The Mattermost bot is a standalone process like the Discord bot — it does not integrate with the orchestrator event loop.
- Mattermost slash commands are detected by message prefix, not registered as server-side custom commands — this avoids requiring Mattermost admin access but means they are not discoverable via Mattermost's slash command UI.
- Each message is stateless — no conversation history is carried between messages (same as Discord).
- The bot connects to a single channel only; multi-channel support is out of scope.
- The `mosty` library is early-stage — API changes may require updates to the bot.

## V12 Acceptance Criteria

- All v1, v2, v3, v4, v5, v7, v8, and v11 acceptance criteria remain.
- `scriptorium mattermost` starts a Mattermost bot with the same chat modes and slash commands as the Discord bot.
- Shared chat logic is extracted to avoid duplication between Discord and Mattermost bots.
- Configuration lives in `scriptorium.json` under `mattermost`.
- `MATTERMOST_TOKEN` environment variable provides authentication.
- Docker compose supports a `mattermost` service.
