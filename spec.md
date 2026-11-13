# Spec

## Adoption Goal

Preserve Scriptorium's implemented behavior as an explicit current-state blueprint. The execution contract follows the ACP implementation described in the repository README and `docs/v20.md`, together with the source and existing tests. Test coverage describes available verification, not a claim that live release gates have passed. Future work is labeled within its relevant topic; release history and validation records belong outside this spec.

## Product Summary

`scriptorium` is a local-first, git-native agent orchestration tool for software projects, implemented in Nim.

- Planning state lives on the orphan `scriptorium/plan` branch, which must never be merged into the project's default branch.
- The workflow is Architect → Manager → Coding agent → Review agent → single-flight merge queue.
- Agents execute through one threaded ACP v1 runtime using ACPort. Codex and Claude use official ACP adapters; Grok uses native ACP stdio. Custom agents use named ACP profiles.
- Git remains authoritative for areas, tickets, dependencies, transitions, merge requests, and default-branch health. Managed worktrees isolate ticket branches. Scoped HTTP MCP tools carry completion signals.

## CLI And Project Initialization

- The CLI exposes `init`, `import`, `run`, `status`, `plan`, `ask`, `do`, `quest`, `dashboard`, `discord`, `mattermost`, `sync`, `worktrees`, `--version`, and `--help`. The `audit` entry point reports that it is disabled pending stabilization.
- `scriptorium init [path]` rejects non-Git repositories and an existing `scriptorium/plan` branch. It creates an orphan planning branch, directory placeholders, and an initial commit.
- The initialized planning structure includes `areas/`, `docs/iterations/`, `services/`, `tickets/open/`, `tickets/in-progress/`, `tickets/done/`, `tickets/stuck/`, `decisions/`, and `spec.md`. Merge queue and health state may be created lazily.
- The current initial spec is `# Spec`, a blank line, and the instruction to run `scriptorium plan` to build the spec with the Architect. Blank or placeholder specs are not runnable.
- Initialization creates missing `AGENTS.md`, a starter Makefile with `build`, `test`, `integration-test`, and `e2e-test` targets, `tests/config.nims`, and source/documentation directories. Generated project scaffolding is committed; existing files are preserved during init.
- Missing `scriptorium.json` is generated from the current defaults and left uncommitted. Initialization lists created artifacts and explains configuration, planning/import, and running.
- Managed Nim projects use `src/`, `tests/`, `docs/`, root `AGENTS.md`, a Makefile, package metadata in a `.nimble` file, and Nimby with `nimby.lock` for dependencies. Starter test targets are placeholders; projects must provide meaningful quality gates.
- Default-branch resolution checks `refs/remotes/origin/HEAD`, then local `master`, `main`, and `develop`. Runtime resolution fails clearly if none resolves. Init attempts to set the origin HEAD when origin exists and currently falls back to `master` if detection fails. All health, diff, prior-work, and merge operations use the resolved branch; references to default-branch health below apply regardless of its name.
- `scriptorium import` reads source, tests, config, README, and relevant documentation, reconciles only `spec.md`, and preserves explicitly marked future work. It does not start workers or create tickets.
- Preflight for `run` checks the plan branch, root `AGENTS.md`, Makefile and its `test:` target, configured ACP executables, Nimby, and the supported compiler floor. Errors give corrective actions. Authentication is established by the selected agent/ACP setup and failures surface explicitly; preflight is not a universal credential validator.

**Future work:** Add the previously planned new-project/`AGENTS.md` explanation to the initial spec placeholder. Stronger make-target dry runs and credential preflight remain planned validation improvements, beyond the current checks.

## Planning, Ask, And Ad-Hoc Operations

- Planning uses the deterministic managed plan worktree at `<repo>/.scriptorium/worktrees/plan`, with the repository root supplied as context for reading project source.
- Both one-shot `plan <prompt>` and interactive `plan` run the Architect in that worktree. One-shot prompts must be nonblank.
- Planning uses an Architect-specific per-repository lock and plan write guards. Ordinary planning writes `spec.md`; direct `tickets/open/` creation is reserved for emergencies where the normal spec → areas → managers flow cannot operate. Disallowed writes are reverted and cause failure.
- One-shot changes use `scriptorium: update spec from architect`. Interactive spec changes create at most one turn commit, `scriptorium: plan session turn <n>`. Unchanged specs produce no spec-update commit.
- Interactive `plan` and `ask` support `/show`, `/help`, `/quit`, `/exit`, unknown slash-command handling without an agent call, streamed status, EOF, and Ctrl+C handling.
- `ask` uses the same plan worktree and repository context, supplies the current spec, enforces read-only agent access plus the no-write guard, and creates no plan commits.
- `import` retains its stricter spec-only post-run allowlist even though ordinary planning permits the emergency ticket path.
- `do` runs in the project root with full access for ad-hoc work, outside the ticket pipeline and plan write guards.
- Interactive production turns use native ACP conversations. Prior assistant replies are not re-embedded into every prompt; injected unit-test runners may use explicit history to test prompt construction.
- `plan`, `ask`, and `do` accept `--resume <session-id>`, subject to the session compatibility and access rules below. Ctrl+C cancels an active interactive turn cooperatively.

## ACP Execution And Configuration

### Shared runtime

- All agent execution, including planning, area generation, management, coding, reviewing, prediction, recovery, chat routing, and the audit agent implementation, uses ACPort. There are no backend-specific subprocess runners or stdout protocol parsers to preserve.
- ACPort owns transport, protocol framing, worker threads, child-process lifecycle, and bounded close. Scriptorium owns operation policy, watchdogs, continuations, completion decisions, and ticket outcomes.
- ACP update callbacks transfer owned payloads through channels to the owning Scriptorium runner thread. Application event handlers run there, preserving event order and draining final updates before reporting completion. Permission decisions use immutable operation policy on the permission worker.
- Structured updates retain their typed content and raw payload, including unknown updates. Display categories include reasoning, tools, messages, status, plans, and diagnostic heartbeats.
- Agent artifacts include streamed ACP JSONL transcripts, separate stderr diagnostic logs, the last assistant message, session identity, and typed completion/failure details. Setup, restored history, and shutdown diagnostics are retained separately from new turn output.
- Results preserve the ACP stop reason and distinguish cancellation, timeout, transport, protocol, RPC, refusal, and limit failures. RPC error code and structured data remain available. A successful `endTurn` is a conversational result, not a ticket submission.

### Named profiles and role settings

- `scriptorium.json` contains named `acpAgents` profiles. A profile defines `command`, an argument array `args`, and environment overrides `env`.
- Optional profile settings are `readOnlyArgs`, `readOnlyMode`, `writeMode`, `modelOption`, `effortOption`, and `authMethod`. Model/effort option identifiers support agents whose options lack standard categories; headless authentication uses the selected method.
- Built-in profiles are `codex` (`codex-acp`), `claude` (`claude-agent-acp`), and `grok` (`grok --no-auto-update agent --no-leader stdio`). Pinned tools are preferred when available; missing executables fail with setup guidance.
- Roles `architect`, `manager`, `coding`, `reviewer`, and `audit` select `agents.<role>.acpAgent`. Each role also supports `model`, `reasoningEffort`, `configOptions`, `hardTimeout`, `noOutputTimeout`, and `progressTimeout`.
- Defaults select the Claude profile, with empty model and effort. Empty/omitted model uses the selected agent's default model.
- Apply explicit models through advertised ACP configuration before effort; refresh dependent options through the session's current catalog. Explicit unsupported models, effort, option identifiers, or values fail clearly. Preserve configured model identifiers rather than silently rewriting them.
- Generic `configOptions` values are advertised string or boolean settings. Access mode is controlled by the profile and operation policy; a generic `mode` override is rejected.
- Supported legacy `harness` values translate on load: `codex` → `codex`, `claude-code` → `claude`, `grok-build` → `grok`. Explicit `acpAgent` takes precedence. Reading configuration does not rewrite files; explicit normalization preserves unrelated keys.
- Typoi and Hermes execution is retired and fails with migration guidance. Model-prefix inference is a legacy test helper, not runtime routing policy. Custom ACP profiles provide the extension mechanism.
- Authentication uses supported Codex OAuth/API keys, Claude OAuth/API keys, and Grok login/`XAI_API_KEY`. AWS Bedrock is unsupported and must not be enabled.

### Runtime settings

- `endpoints.local` defaults to `http://127.0.0.1:8097` for the shared MCP HTTP host.
- `concurrency.maxAgents` defaults to 4 and governs the shared manager/coder slot pool. `concurrency.outputBudgetMB` defaults to 0, meaning unlimited.
- Coding defaults are 14,400,000 ms hard timeout, 300,000 ms no-output timeout, 600,000 ms progress timeout, and 5 attempts. The `timeouts` object exposes `codingAgentHardTimeoutMs`, `codingAgentNoOutputTimeoutMs`, `codingAgentProgressTimeoutMs`, and `codingAgentMaxAttempts`.
- Architect defaults are 7,200,000 ms hard and 600,000 ms no-output; manager/reviewer defaults are 3,600,000 ms hard and 300,000 ms no-output. Coding, area-Architect, and manager requests pass role progress deadlines to the runtime. Interactive Architect and current review requests do not pass that field.
- Other current config groups include `loop`, `remoteSync`, `dashboard`, `discord`, `mattermost`, `devops`, disk-space protection, and `syncAgentsMd`.
- `logLevel` and `fileLogLevel` are overridden by `SCRIPTORIUM_LOG_LEVEL` and `SCRIPTORIUM_FILE_LOG_LEVEL` respectively. Tokens and credentials for chat transports come from the environment, never from config.

## Permissions And Operation Write Guards

- Permission responses are per action (`allow_once` or `reject_once`), rather than durable grants. If the required decision is unavailable, the permission is cancelled.
- Read-only operations permit clearly classified read, search, fetch, and think actions, and reject mutating or ambiguous actions. They also require an enforceable advertised restricted mode or explicitly configured launch restrictions; a prompt requesting read-only behavior is insufficient.
- Codex uses its read-only mode; Claude uses plan mode. Grok does not advertise ACP modes, so its read-only profile supplies tool-deny launch arguments. A custom profile unable to enforce read-only access fails that operation.
- Restricted planning edits require reported locations, all within allowed write paths. Path checks resolve existing ancestors and symlinks to prevent traversal or symlink escapes.
- Full-access operations, including `do` and ticket coding, receive their full operation policy. Read-only and restricted sessions cannot be reused as full-access sessions.
- ACP permissions supplement the existing post-run operation guards: planning's allowed prefixes, import's spec-only allowlist, ask's no-write check, and narrowly scoped orchestrator writes to the plan branch. Preserve the main repository's existing dirty state during planning/management operations.

## Native Sessions And Persistence

- Reuse an ACP session only for the same conversation/operation, role, assignment, working directory, agent profile/settings, and access policy. Coding identity includes ticket and branch; changes to model, effort, config options, executable/profile, or write scope invalidate compatibility.
- Interactive conversations and coding continuations retain native state across turns. A coding assignment keeps its scoped MCP endpoint registered across its turns; independent assignments have independent sessions and completion state.
- Private runtime records persist session ID, hashed compatibility identity, working directory, completion status, and update time. Persisted identity excludes credential values and scoped MCP URLs. Session state is managed outside tracked project files, using managed session directories and Git runtime metadata.
- Explicit resume requires a known matching record. Interrupted coding assignments automatically look for a matching saved session.
- Restore through ACP `loadSession` only when advertised. A restored session receives fresh scoped MCP configuration. If session loading is unavailable, report a fresh recovery conversation and supply current repository, ticket, and prior-work context.
- Replayed history during setup is not a new assistant reply or new turn output. Session compatibility checks remain in force after restart.
- Successful merge completion retires saved assignment sessions so completed work is not inadvertently resumed.

## Orchestrator And Planning Artifacts

### Run loop and health

- `run` starts repository logging, the local MCP HTTP server, and a continuous polling loop with idle sleep. Startup recovery precedes the first tick.
- Normal scheduling requires the plan branch, a runnable spec, sufficient disk space, an unpaused orchestrator, and a healthy resolved default branch. A missing/placeholder spec reports `WAITING: no spec — run 'scriptorium plan' or 'scriptorium import'`.
- Tick phases collect worker completions, evaluate scheduling/health gates, run Architect area synchronization, start eligible managers, assign eligible coding work using remaining slots, and process at most one merge-queue item. Managers/coders can remain active across ticks.
- Architect work is sequential, at most once per tick under the plan lock, and completes before managers start. Review/merge is strictly sequential. A single long-running coding agent must not block scheduling of independent work when the shared pool has capacity.
- Pause stops new assignments while completions and merge-queue processing can continue. Remote sync is explicitly configured and disabled by default; enabled sync performs fetch/merge/push against configured remotes.
- Default-branch health runs `make test` then `make integration-test` on its managed worktree. A failed required target blocks ordinary new work. Recovery-area work is allowed to repair an unhealthy default branch, through the same coding submission, review, and merge gates.
- Cache health in memory by HEAD and persist it in `health/cache.json` on the plan branch. Records contain health, timestamp, both target exit codes, and wall times. Cached healthy and unhealthy commits skip reruns; a new HEAD triggers lookup/checks. Cache updates use `scriptorium: update health cache`, retaining the most recent 100 entries.
- When feedback looping is enabled and work drains, run the configured evaluation command and ask the Architect to revise the spec. `loop` defines `enabled`, `feedback`, `goal`, `maxIterations` (0 unlimited), and `feedbackTimeoutMs` (default 7,200,000). Quest mode evaluates its requested goal through the corresponding loop.
- The automatic audit trigger and `audit` CLI remain disabled. Their agent implementation uses ACP.

**Future work:** Stabilize and validate the audit workflow before enabling its entry points. ACP migration does not itself authorize enabling it.

### Authoritative Git layout

- The plan branch stores `spec.md`, `areas/*.md`, tickets in exactly one of `open/`, `in-progress/`, `done/`, or `stuck/`, `decisions/`, `queue/merge/pending/*.md`, `queue/merge/active.md`, and `health/cache.json`.
- Ticket IDs are monotonic and zero-padded across all states. Merge queue IDs are monotonic and zero-padded; pending items are processed FIFO by queue ID.
- Area IDs come from area filenames. Ticket markdown links ownership through `**Area:** <area-id>` and dependencies through `**Depends:** <id-list>`.
- Ticket assignment moves `open → in-progress`, creates/reuses `scriptorium/ticket-<id>`, and records `**Worktree:** <absolute-path>`. Ticket paths, IDs, branch, worktree, and submit summary are retained in merge metadata.
- Managed paths are deterministic under `<repo>/.scriptorium/`, including `worktrees/plan`, `worktrees/tickets/`, locks, logs, and private runtime state. Temporary-directory paths in the older spec are superseded. Cleanup handles stale managed worktrees and recoverable Git registration/lock residue without discarding active assignments.
- State changes are orchestrator-owned transitions committed on the plan branch. The journal protocol adds begin/cleanup commits around the logical transition commit; the old single-total-commit assumption does not apply.

### Spec-to-area-to-ticket synchronization

- Areas are persistent ownership zones. The Architect writes area files directly; managers deliver ticket documents through MCP and the orchestrator writes them under `tickets/open/`.
- `areas/.spec-hash` stores the SHA-1 of runnable `spec.md`. Missing areas trigger generation; subsequent passes run on changed spec content. Area updates and the hash marker are committed. Existing areas without a marker are adopted by recording the current hash without regenerating them.
- `tickets/.area-hashes` stores sorted `area-id:hash` records. Changed/missing area hashes make areas eligible for new tickets even if earlier tickets are done; open/in-progress work for an area suppresses concurrent re-ticketing.
- Legacy state without area hashes uses existing ticket linkage to avoid duplicate work. Bootstrap records hashes for already-ticketed areas, leaving unticketed areas eligible. A fresh area generation initializes an empty hash map so new areas are eligible immediately.
- Manager invocations handle one area each, reading a snapshot without holding the plan lock during agent execution. Different areas may run concurrently. The orchestrator validates area linkage, assigns filenames/IDs, and commits returned documents and hash updates under brief plan locking.
- Managers submit markdown strings through their area-scoped `submit_tickets` tool. Agent-generated numeric filenames and stdout are not sources of ticket identity or completion.

## Assignment, Concurrency, And Resource Accounting

- Scan open tickets oldest-first, skipping unsatisfied dependencies and occupied areas. Dependencies must reach `done/`; detect cycles at creation/periodic scans and surface cycles and ordinary waits in status.
- Tickets in the same area are serialized. Different areas may execute concurrently, each in an isolated ticket worktree and branch. Area separation cannot detect every shared-file conflict; merge reconciliation handles those conflicts.
- Managers and coders share `concurrency.maxAgents`. With two managers in a pool of four, two slots remain for coders. Reap finished workers and interleave manager/coder starts across ticks instead of waiting for every manager to finish. A value of 1 provides serial operation.
- Track each worker and its role, ticket/area identity, branch/worktree, and outcome. Log slot occupancy on starts and finishes. Sequential Architect and review/merge stages preserve plan/default-branch safety.
- Count structured transcript bytes as protocol events are received during active turns across all roles, including concurrent workers. Keep per-run `outputBytes`, ticket `output_bytes`, and an atomic cumulative session counter.
- `concurrency.outputBudgetMB` is a transcript-volume cap in units of 1,048,576 bytes. At or above a positive cap, pause new coding ticket assignments, log exhaustion, and let running agents finish. Completing tickets does not replenish the session counter. Other roles' output contributes to the cap; this is not a global stop switch for all agent calls.
- Deprecated `concurrency.tokenBudgetMB` is accepted only when `outputBudgetMB` is absent. The canonical field wins. Output bytes measure neither tokens, provider quota, nor monetary cost.
- Stderr, synthetic heartbeats, and restored setup history do not consume the turn-output budget. Provider failures follow typed ACP handling; no stdout-based rate-limit scanning or orchestrator exponential-concurrency policy is part of the current runtime.

**Future work:** Calibrated difficulty-based routing, adaptive concurrency, and actual token/cost accounting are distinct possible extensions, not implemented effects of transcript-byte accounting. Do not introduce them through the deprecated budget alias.

## Scoped MCP Completion

- MCPort serves JSON-RPC over HTTP POST (Streamable HTTP); SSE is unsupported. Pass scoped HTTP connections in standard ACP `mcpServers` on session creation and restoration, with HTTP type. Backend-specific MCP launch flags are superseded.
- Each registered MCP endpoint is bound to one role and assignment. Coding exposes `submit_pr`; manager exposes `submit_tickets`; review exposes `submit_review`; audit exposes its report tool. The caller cannot choose a different ticket/area through completion arguments.
- Private endpoint tokens isolate simultaneous sessions. Unregistering a session expires the endpoint. Duplicate completion calls retain the first accepted result.
- Coding completion requires `submit_pr` with a nonempty trimmed `summary`. Natural-language claims, stdout, process exit, and a normal ACP turn completion cannot enqueue a review request.
- Before replying successfully to `submit_pr`, atomically persist and sync a durable pending receipt containing ticket ID, branch, and summary in managed ticket runtime state. Receipts contain no credentials or scoped MCP URLs.
- A matching pending receipt restores submission state when the coding MCP session is registered again. Enqueue the merge request through the Git transition, then mark the receipt consumed. This recovers the gap between a successful MCP response and queue enqueueing.
- The implemented handler records completion; it does not run the old blocking pre-submit `make test` check. Quality gates remain mandatory in merge processing, and `make test` also runs before coding stall continuations.

## Coding Continuations, Watchdogs, And Recovery

### Turn supervision

- Hard deadlines bound turn duration; no-output deadlines measure incoming protocol activity; progress deadlines measure tool-call/tool-update activity. Use monotonic time. Reasoning/message chatter cannot reset the tool-progress timer, and stderr and synthetic heartbeats reset neither watchdog.
- Every role uses the shared runtime's available watchdogs according to its request deadlines. The setup handshake has a bounded overall deadline. Do not claim a ten-minute progress watchdog for invocations that do not supply it.
- On cancellation or watchdog expiry, send cooperative ACP cancellation, drain events, allow a five-second grace period, and then use ACPort's bounded close if necessary. ACPort settles pending work and joins callbacks before Scriptorium releases channel state.
- A connection that cooperatively settles cancellation may be reused for a compatible later turn. Transport loss closes that connection. Keep transport/process cleanup within ACPort rather than adding manual backend process-killing logic.
- The shared one-shot runner bounds retries for timeout/transport failures by `maxAttempts`, retaining compatible native conversation state and continuation context. RPC/protocol/refusal failures do not become unrestricted transient retries.

**Future work:** Complete the previously intended progress-watchdog coverage for planning/ask/do and review invocations. Establish regression coverage of their current request/deadline behavior before extending propagation; a shared runtime capability alone does not establish per-operation coverage.

### Coding assignment recovery

- Coding prompts include ticket path/content, repository root, assigned worktree, and any prior work. Run in the ticket worktree and append structured run notes on the plan branch after each attempt.
- A coding turn ending without its scoped submission is incomplete. Within the configured attempt limit, send a distinct continuation including original ticket context, current instructions, and the reminder to call `submit_pr`.
- Before a retry continuation, run `make test` in the ticket worktree. Include passing status or bounded failure output and a directive to fix failures. This coding-specific check augments the merge gates; it is not a manager/Architect test gate.
- User cancellation stops continuation. Permanent RPC/protocol/refusal outcomes are not blindly retried. Exhausted or terminal incomplete assignments reopen with failure notes and metrics; repeated workflow failures can park tickets in `stuck/`.
- Before retries, validate Git worktree state. Recreate corrupt worktrees from the ticket branch and commit partial uncommitted work as `scriptorium: save partial agent work (attempt <n>)` when needed.
- At assignment execution, detect commits ahead of the resolved default branch, preserve the branch tip, and tell the agent to inspect and build on existing work. Review feedback is included in later ticket context; matching saved coding sessions can be restored with a fresh MCP endpoint rather than always starting from scratch.
- Manager completion uses `submit_tickets`; Architect area output is checked through the area synchronization flow. The earlier universal file-creation-stall retry promise is superseded by ACP failure handling and these operation-specific completion paths.

### Startup and Git transition recovery

- Before polling: clean stale Git locks/orphaned managed worktrees; clear dead PID markers; reconcile the plan branch; complete already-merged tickets; and reopen interrupted, unmerged, unqueued assignments. Emit a recovery summary, including a clean-start summary when no action was needed.
- Leave live unknown/orphaned processes running and report their identity for operator review. Stale-marker handling is not backend CLI process management.
- Reconcile `.scriptorium-journal.json` first when present. Without a journal, commit dirty planning state using `scriptorium: recovery commit (unclean shutdown)`.
- For already-merged ticket branches, finish the plan transition to `done/`, remove pending metadata, and clear matching active metadata. Clean active markers referencing absent queue entries. Reopen orphaned in-progress tickets while preserving their branch for subsequent recovery.
- Normal ticket/queue transitions use a write-ahead journal recording operation, timestamp, write contents/hashes, moves, removals, and transition commit message. Commit the journal before mutations, commit the logical state transition, then remove the journal in a completion commit.
- Replay/rollback is deterministic from applied filesystem steps: complete fully applied transitions, replay remaining steps of partial transitions, and roll back transitions with no applied steps. Successful transitions remove the journal.
- Private ACP session records and MCP receipts use atomic runtime persistence separately from the Git journal. Neither replaces Git ticket/queue state or the default-branch merge gates.
- On orchestrator SIGINT/SIGTERM stop scheduling, wait for workers, log session statistics, and shut down HTTP cleanly. Join server/callback ownership before releasing resources; do not rely on allocator timing or sleep-based shutdown workarounds.

## Review And Merge Queue Safety

- Process at most one pending queue item per pass, FIFO, with active metadata identifying it. Every candidate goes through review before default-branch synchronization and required quality checks.
- Review receives ticket content, the diff against the resolved default branch, area context, submit summary, project instructions, and spec context. Empty/unavailable diffs are represented in the prompt without crashing the pipeline.
- The scoped `submit_review` actions are `approve`, `approve_with_warnings`, and `request_changes`. Change requests require feedback. Feedback is bounded to 4096 bytes with a truncation marker; outcomes, feedback/warnings, agent details, and bounded reasoning are persisted in review notes.
- Missing review completion is treated as a change request with explanatory feedback. A stalled/failed reviewer does not silently approve work.
- Approvals, including approvals with warnings, proceed to merge gates. Change requests remove the current queue item, reopen the ticket with feedback, and count toward retry/parking policy. Later coding uses the same branch and prior work, restoring a matching conversation where supported. Repeated review rejection can park the ticket in `stuck/`.
- Before merging, merge the resolved default branch into the ticket branch, then run `make test` and `make integration-test` in that worktree, in order. Only passing gates allow a fast-forward merge into the default branch and `in-progress → done`.
- Conflicts or test failures append submit summary and bounded output tails and reopen the ticket, or park it after repeated failures. One ticket's failure does not change other running agents or unrelated queue entries.
- Clean pending/active metadata after success, failure, or stale-item processing. A queued ticket already in `open/`, `done/`, or another terminal state is stale and must not be merged again.
- Recover a missing ticket worktree from its branch when possible; otherwise reopen with failure context. Cleanup removes non-active worktrees and stale registrations while protecting active work.
- Parallel coders work on their own branch tips. Merge-time default-branch synchronization remains the correctness gate after other tickets land; running agents do not require a global branch reset.
- Unhealthy-default-branch recovery creates a focused recovery-area ticket with failure context and executes it with Architect settings. Duplicate/exhausted recovery work is suppressed; fixes still require scoped completion, review, and tests.

## Observability, Metrics, And Status

- Forward ACP tool, file-location, plan, and status events to INFO logs during execution, prefixed with role and ticket/area identity. Reasoning, message, and unknown updates remain in structured transcripts and available to event consumers; the orchestrator log forwarder skips them and synthetic heartbeats. Stderr remains in separate diagnostics.
- Repository orchestrator logs live under `.scriptorium/logs/orchestrator/run_<UTC timestamp>.log`; role-specific artifacts retain structured transcripts and last-message files.
- Each tick logs one INFO summary with Architect/manager state, coding identity/status or pool utilization, merge activity, open/in-progress/done counts, and human-readable durations where available.
- Log lifecycle events at INFO: assignment, coding start/finish and attempt, stall detection, pre-retry tests, continuation, scoped submission, queue entry, review decision, merge start/result, completion, reopen, and parking. Include identity, timing, test exit codes, and failure context as applicable.
- Agent run notes retain model/backend context, ACP session ID, attempt/count, result exit code, timeout/failure details, transcript bytes, log and last-message paths, and a bounded last-message tail. The result exit code represents operation success/failure, not a backend CLI contract.
- Ticket metrics include `wall_time_seconds`, `coding_wall_seconds`, `test_wall_seconds`, `attempt_count`, `outcome` (`done`, `reopened`, `parked`), `failure_reason`, `model`, and `output_bytes`. Failure reasons include stall, test failure, merge conflict, hard/no-output/progress timeout, and parking. Timing is numeric seconds; transcript bytes are not a token proxy.
- Lightweight ticket prediction uses the configured coding ACP profile with ticket, area, and spec context. Persist/log `predicted_difficulty` (`trivial`, `easy`, `medium`, `hard`, `complex`), `predicted_duration_minutes`, and reasoning before coding. Prediction failure must not indefinitely block assignment.
- Post-analysis compares available predictions with outcome, attempts, and elapsed time, recording actual difficulty, `accurate`/`underestimated`/`overestimated`, and a brief summary. Tickets without predictions skip comparison. Estimates remain heuristic.
- Shutdown logs two session-summary lines: uptime/ticks/completed/reopened/parked/queue counts, then average ticket/coding/test wall time and first-attempt success. Empty sessions show zero or unavailable averages. Session averages are not cumulative historical telemetry.
- `status` preserves counts, active ticket ID/path/branch/worktree, elapsed time, recent outcomes/timing (default five), first-attempt success rate, and blocked/waiting dependencies. Prefer the active queue item, then in-progress work, for active-ticket resolution; no active ticket prints `Active Agent: none`.
- `worktrees` lists active in-progress worktree/ticket/branch mappings, or `scriptorium: no active ticket worktrees`. The dashboard presents repository workflow state, agents, and logs.

## Testing And Engineering Baseline

- Before planning feature changes, inspect relevant tests. Where behavior lacks a baseline, require prerequisite regression coverage before feature changes through the normal spec-to-manager flow. Documentation reconciliation does not itself require new feature tickets.
- Offline unit tests (`tests/test_*.nim`) use injected runners, mocks, and the independent ACP protocol peer. They must not call live AI services. Mocking a core dependency makes a test a unit test even if a subprocess transports its fixture protocol.
- `tests/test_agent_runner.nim` covers ordered callbacks/final chunks, native turns, restore without duplicate replies, model/dependent effort selection, read-only and restricted permissions including symlinks, transport/RPC errors, bounded retries, cancellation/reuse, stderr isolation, unknown updates, session compatibility/retirement, and retired runners.
- Config tests cover read-only migration, explicit-profile precedence, unknown-key preservation, unsupported runners, and budget aliases. MCP tests cover scoped catalogs, assignment binding, duplicate completion, durable receipt recovery/consumption, feedback bounds, and endpoint expiry. Shared-state tests cover cumulative budgets and uninterrupted running agents. Existing planning, continuation, review, queue, journal, dependency, and recovery tests protect workflow behavior.
- `make test` runs offline unit tests with bounded parallel jobs. `make test-arc` and `make test-orc` exercise the shared ACP ownership/lifecycle suite under both memory managers.
- Real integration tests (`tests/integration_*.nim`) exercise actual Git, HTTP, ACP adapters, and services. They do not replace their core dependencies with mocks/fakes. Missing prerequisites, missing credentials, provider errors, and shutdown failures fail explicitly; environment flags do not skip categories.
- `make integration-test` runs real component suites and the named Codex, Claude, and Grok ACP suites. `make integration-test-codex`, `integration-test-claude`, and `integration-test-grok` select one backend explicitly.
- Live ACP coverage includes streaming, explicit settings, permissions, native multi-turn state, persisted restore with fresh scoped MCP, real completion tools, cancellation/reuse, concurrent isolation, and clean shutdown. Real review and coding submission tests protect the scoped completion paths.
- `make e2e-test` runs a real small spec-to-merge workflow for each supported backend; `make e2e-test-codex`, `e2e-test-claude`, and `e2e-test-grok` select one. Fresh-repository flows use `scriptorium init` and verify its scaffolding before proceeding through planning, coding, review, tests, and merge.
- Build/PR CI runs offline tests, ARC coverage, and a build; push packaging emits the Linux binary. Trusted default-branch/manual integration and E2E workflows install locked tools and require OpenAI, Anthropic, and xAI credentials. ORC remains an explicit validation target even where CI currently runs ARC only.
- Run each suite once per validation stage; rerun for failures after fixes or relevant changes. Existence of live tests is separate from a successful live run. Keep local diagnostic/test artifacts out of tracked files; architect scratch output belongs in `/tmp`.
- Maintain focused modules for Git, locks, metadata, prompts, ACP/runtime permissions/sessions, agent pools, role execution, merge queue, health, recovery/journaling, logging, and interactive sessions. Refactoring preserves public behavior and the Git/quality contracts; historical extraction sequences are not ongoing product requirements.

## Dependencies And Packaging

- Use Nim >= 2.2.14 and Nimby >= 0.2.3; Docker/CI pin their compiler and Nimby toolchain. Dependencies include ACPort >= 1.1.1, MCPort >= 1.2.0, jsony, mummy, guildy, and mosty. Prefer these existing libraries for their supported tasks.
- `make setup` installs exact `nimby.lock` revisions into isolated `.build/nimby`, verifies commits, and generates local compiler configuration without changing global Nimby packages.
- `make agent-setup` installs exact CLI/official-adapter versions from package locks under `.build/agent-tools`, preserving global installations. Node >= 22 is required; Docker/CI use Node 24. Docker includes the compiler, agent tools, adapters, and locked dependencies.
- Compose mounts the repository and existing Codex, Claude, and Grok credential locations. Rebuild for Scriptorium or lock changes; credentials remain external. `make check-updates` reports package updates without changing pins.
- The current Dockerfile still uses a `latest` Monolab base image. Locked compiler/tools/dependencies do not make that base immutable.

**Future work:** Pin the remaining Docker base image tag or digest and add startup reporting of the base/tool versions to finish the existing reproducibility and traceability goals. Full image reproducibility is not implemented while that base floats.

## Chat Frontends

- Discord (`guildy`) and Mattermost (`mosty`) are standalone frontends using shared transport-independent mode parsing, Architect invocation, and status/queue/pause handling.
- `plan:` (default) uses guarded planning, `ask:` uses enforced read-only access, and `do:` uses full repository access. All invoke the shared ACP runtime with the corresponding operation policy.
- `/status`, `/queue`, `/pause`, and `/resume` operate directly on workflow state without an LLM call. Mattermost recognizes command prefixes rather than requiring server-side slash registration.
- Filter messages by configured channel and allowed users; ignore the bot's own posts. Run agent work off the gateway thread and truncate replies to transport limits (Discord 2000 characters, Mattermost 16383).
- Config groups provide server/base URL, channel, allowed user IDs/names, and bounded chat context. Tokens are `DISCORD_TOKEN` and `MATTERMOST_TOKEN`. Each message routes its own operation; native CLI conversation reuse does not imply cross-user chat session reuse.
- Docker Compose provides chat services with workspace/credential mounts and environment-provided tokens. Chat transport does not own the orchestrator event loop or bypass plan/Git invariants.
