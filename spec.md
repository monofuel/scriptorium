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
