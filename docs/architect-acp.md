# Architect over ACP

`scriptorium architect-acp` lets an ACP client hold one conversation with a
repository's Architect. The client talks only to the Architect. Managers,
coders, reviewers and the merge queue remain Scriptorium's own agents, run by
the orchestrator with Scriptorium's own MCP endpoint.

## Process shape

One container serves one repository.

- `scriptorium run --paused` is the owned supervisor. It writes the pause flag
  before its loop, so it admits no new work until started.
- `scriptorium architect-acp` attaches separately over stdio, without a TTY,
  for example `docker exec -i <container> scriptorium architect-acp`.
- `scriptorium guildhall-control start|pause|status` changes admission and
  prints structured JSON status. `start` fails when no orchestrator is running.
- Stopping the container stops every child. Neither command cleans PID files,
  worktrees or locks just to begin a conversation; `architect-acp` reports
  existing hazards on stderr at startup.

Pause means no new assignments. In-flight agents finish and the merge queue
keeps draining, as with `/pause` in the chat bots.

## Status and safe reconfiguration

`guildhall-control status` reads two orchestrator-owned files under the
ignored `.scriptorium/` directory:

- `orchestrator.pid`: the run guard, JSON `{pid, timestamp}`. A bare decimal PID
  is still accepted. `orchestrator.running` means that PID is alive.
- `orchestrator-runtime.json`: one snapshot the orchestrator loop replaces
  atomically at its phase boundaries. It records the owner PID and kernel
  start time, the current phase, whether a pause was observed, and the pool's
  actual managers, coders and audits with their ticket or area.

The snapshot counts only when its owner PID matches the PID file and that live
process has the recorded start time. Otherwise `orchestrator.runtimeVerified`
is false, `agents.source` is `unavailable` and `agents.agents` is empty.
In-progress tickets from the plan branch are listed separately as
`tickets.inProgressTickets` and are not presented as running agents.

`orchestrator.quiescent` is true only when all of these hold:

- the snapshot is verified;
- the pause flag is set now;
- the loop observed that pause at a tick boundary, then finished that tick's
  merge handling with no pool worker (including finished workers whose
  completion is unprocessed), no pending merge item and no active merge marker.

Every tick writes a non-quiescent snapshot before it reads the pause flag or
starts work, so a quiescent snapshot from before a `start` cannot outlive the
first tick that admits work. Pause, then wait for `quiescent` and an idle
Architect (`architect.turnActive` false) before recreating or reconfiguring the
container. Stopping the container remains the container owner's decision.

Limits:

- Owner verification reads `/proc`. Without it (non-Linux, or a status call in
  another PID namespace) the snapshot never verifies and `quiescent` stays false.
- While available disk space is below `diskSpaceMinGB` the loop skips the pause
  branch, so quiescence is not reported until space recovers.
- A long synchronous phase (architect, merge tests, recovery) keeps its phase
  until it returns; the snapshot is not a progress heartbeat.

## Turns

Each prompt runs on one owner thread that owns every native conversation, Git
operation and lock. ACP request workers relay jobs, streamed updates and
interactions; they never run turn logic. A turn takes the admin lock, runs the
same plan or ask turn as `scriptorium plan` / `scriptorium ask`, commits under
the commit lock only after success, and releases the admin lock before the
reply. The orchestrator is therefore never blocked between turns.

Message, thought, tool call and plan updates stream with the outer session
identity. User-message echoes, adapter command catalogs and heartbeats are not
forwarded.

An Architect turn must produce nonempty assistant text after its last tool
activity before `end_turn` can count as a completed answer. Earlier commentary
remains in the transcript but cannot stand in for a final answer. A failed tool
may be recovered, or the Architect may explain that failure in its final answer;
tool failure alone does not discard a valid explanation. This conversational
requirement does not apply to internal coding completion through `submit_pr`.

Only cancellation requested by the outer client returns `cancelled`. Native
cancellation without that request is an ACP error, including cancellation after
a locally rejected permission. Timeouts and relay failures remain errors.
Receipts and error data retain `cancellationSource`, `nativeStopReason`,
`failedTools`, and `deniedPermissions`; `client`, `native`, `timeout`, `relay`,
and `shutdown` are distinct sources. A `client` cancellation records the protocol
request, not an inference about whether a human or another caller initiated it.
Original receipts are never rewritten or automatically retried.

Account/model metadata checks do not prove native tools can run inside a
container. In particular, a nested Codex sandbox may fail to create namespaces.
Qualify real file-tool execution and final-answer delivery on disposable state
under the actual container isolation contract before claiming readiness. Do not
enable host user namespaces, relax global security settings, or approve an
ambiguous execute permission to conceal a failed read-only tool.

The Architect provides a private `scriptorium-project` HTTP MCP server through
standard ACP `mcpServers` session parameters when the native agent supports
HTTP. The server name is reserved so caller-supplied MCP setup cannot replace
this capability. It exposes only:

- `get_spec {}`: the actual current plan worktree's `spec.md`.
- `read_project_file {path, line?, limit?}`: tracked UTF-8 project text, with
  one-based line pagination (200 lines by default, at most 500).

Reads reject private runtime and credential paths, untracked files, traversal,
absolute paths, symlinks in any path component, binary data, nonregular files,
and files above 1 MiB. File descriptors use `openat`/`O_NOFOLLOW`; no shell or
write operation is exposed. Each outer conversation has a fresh scoped token;
setup/close unregisters it, and the process owns and stops the loopback host.
No scoped URL is stored in durable session identity or outer transcripts.
Restricted native shell execution may still be unavailable in the container;
the reader does not change that security policy or promise working shell or
planning-write tools.

Source-origin terminal error data includes `origin: scriptorium-architect` and
a `terminal` descriptor with `delivery`, `outcome`, `reason`,
`nativeStopReason`, `cancellationSource`, and `finalAnswerPresent`. Successful
and client-cancelled replies carry the descriptor under `_meta.scriptorium`.
`delivery: accepted` describes receipt of the request, not a successful answer;
the terminal outcome and answer-presence fields establish that distinction.

The explicit `tests/integration_architect_container.nim` acceptance takes a
disposable container, a common host/container fixture-root path, the project
config JSON, and the container's Scriptorium executable. It creates synthetic
Git/spec state, commits a random file-only nonce, and requires a real native
MCP read followed by the nonce in a final answer. The owner provisions the
unchanged production isolation/authentication and tears the replica down; the
test closes its own ACP session and removes its synthetic state. It must never
target a human chat or start an orchestrator.

Commands answered without the model: `/status`, `/queue`, `/start`, `/pause`,
`/show`, `/help`.

## Modes and policy

The session exposes one setting, `mode` (`plan` or `ask`), both as a config
option and as a legacy mode. Plan may write `spec.md` and `tickets/open`; ask is
read-only. Each mode has its own native conversation because access policy is
part of native session identity.

The engineer still sees one conversation. When a mode's native conversation
runs after turns it did not see, the turn is prefixed with those visible
exchanges from the other mode (bounded, text only), labelled as context that
authorizes nothing. Ask mode stays read-only even if plan-mode requests appear
there, and plan mode treats earlier questions as questions, not instructions.

Native permission requests are first decided by that policy. Only requests the
policy allows reach the client, offered as allow-once or reject-once, so a
client answer can narrow but never widen access. Post-turn write guards still
revert anything outside the allowlist.

Structured questions are relayed per mode, and only the modes the client
advertised are advertised to the native agent. Form questions pass through
unchanged and the client's answer is validated by ACPort. URL consent requests
carry the native `elicitationId` and URL; only `http`/`https` URLs are asked,
others are declined without reaching the client. Scriptorium never opens a URL.
When the native agent later sends `elicitation/complete`, the bridge forwards it
on the client connection, including between turns. ACPort tracks outstanding
flows on both connections, so a completion for a flow the client declined or
never saw is refused and logged rather than reported as success.

## Content, tools and instructions

Prompt capabilities mirror what the configured Architect agent advertises at
startup; images and other blocks are sent to it unchanged after the built
prompt text. MCP servers from `session/new`, `session/load` or `session/resume`
are passed to the native session when the agent supports their transport.
Appended system instructions use the native system prompt when advertised and
otherwise precede the engineer's message. Neither is persisted.

## Durability

`.scriptorium/architect-acp/<session>.json` holds session metadata and
`<session>.jsonl` holds the ordered user content, assistant replies and turn
receipts. `.scriptorium/` is gitignored by `scriptorium init`, and the
directory is private to the server's user.

Prompt images are validated before anything is recorded: PNG, JPEG or WebP by
signature, at most 4 MiB and 8000 pixels per side, at most 8 per message and
16 MiB per message, with the declared type matching the bytes. These are
Guildhall's inbound image limits. Each image is written once to
`<session>-media/<sha256>` (mode 0600) and the transcript entry for that exact
message records only type, digest, byte count and dimensions. Resource links are
recorded as URI and name and are never read; embedded resources and audio are
recorded as labels.

`session/load` replays each user message block by block: text, resource links,
and image blocks rebuilt from the stored bytes. Replay accepts only a 64-digit
digest as the file name and re-checks size, digest, type and dimensions; a
mismatched or missing file is replaced by a notice and logged, never read from
elsewhere. Client MCP servers, headers and system instructions are never
written. The native agent's own history is restored through the existing native
session records, not replayed.

A turn writes a start receipt before running and an outcome receipt after. A
start receipt with no outcome means the process died mid-turn and the effects
are uncertain. The next prompt marks it interrupted; if that prompt is
identical, it is declined with an explanation instead of being re-executed, and
sending it again runs it deliberately. A different prompt runs with a note
telling the Architect the earlier outcome is uncertain.

Only `session/prompt` runs work. `session/new`, `load`, `resume`, `list` and
reconnecting run nothing; load only replays. A broker that reconnects and
resends a prompt whose start receipt is unresolved gets the decline above.
Identical prompts after a recorded outcome are ordinary new requests and run.

## Fresh container contract

One container per repository, with the repository mounted at its own absolute
host path (not `/workspace`) so worktree, plan and session paths recorded in
`.scriptorium` stay valid across container recreation.

- The full binary must be on `PATH` as `scriptorium`; `architect-acp` and
  `guildhall-control` are subcommands of it, not separate executables.
- `HOME=/home/agent`, private to the container user. Copy in only the Claude
  subscription login (`~/.claude/.credentials.json` and `~/.claude.json`),
  not the operator's whole `~/.claude`. Do not set `CLAUDE_CODE_USE_BEDROCK`
  or `ANTHROPIC_API_KEY`; `architect-acp` refuses to start with Bedrock set.
- Persist `HOME/.claude` with the container if native Architect history should
  survive recreation. Without it the outer conversation, images and receipts
  still replay, but the native agent starts a fresh conversation.
- Pin agent CLIs with `make agent-setup` in the image; put
  `.build/agent-tools/node_modules/.bin` on `PATH` (or set
  `CLAUDE_CODE_EXECUTABLE`) so `claude-agent-acp` and `claude` resolve.

Boot, in the repository directory:

```sh
git rev-parse --verify scriptorium/plan || scriptorium init   # this repo only
scriptorium run --paused        # supervisor; admits nothing until started
scriptorium architect-acp       # attached separately: docker exec -i <c> scriptorium architect-acp
scriptorium guildhall-control status|start|pause
```

Initialize only the explicitly selected repository, and only when its
`scriptorium/plan` branch is absent; `init` refuses an existing plan branch.
Never copy another checkout's `.scriptorium/` directory into a new container:
it carries PID files, worktrees, locks and sessions belonging to other
instances. `init` commits any missing starter files (`AGENTS.md`, `Makefile`,
`tests/config.nims`, `src/`, `docs/`) to the current branch and appends
ignore entries to `.gitignore`; a fixture repository should already contain
real `AGENTS.md` and `Makefile` with a passing `make test`.

All roles on subscription Claude, in `scriptorium.json`:

```json
{
  "agents": {
    "architect": {"acpAgent": "claude", "model": "claude-opus-5-5"},
    "manager":   {"acpAgent": "claude", "model": "claude-opus-5-5"},
    "coding":    {"acpAgent": "claude", "model": "claude-opus-5-5"},
    "reviewer":  {"acpAgent": "claude", "model": "claude-opus-5-5"}
  },
  "concurrency": {"maxAgents": 1}
}
```

The model is applied through the agent's own `model` config option; a value it
does not offer fails the turn loudly rather than falling back. An empty model
keeps the subscription default.

Small acceptance run: in plan mode, ask the Architect for one tiny ticket (for
example a one-function change with a test); confirm `/status` shows it open;
send `/start`; watch `/status` and `/queue` until the manager, coder and
reviewer finish and the merge queue lands it on the default branch with
`make test` green; then `/pause`.
