# Integration Test Issues

## IT-LIVE-03: Real daemon path hangs during coding agent execution

### Symptom

`integration_orchestrator_live_submit_pr.nim` test `IT-LIVE-03` hangs for the full 300s `PositiveTimeoutMs` poll window and then fails with:

```
orchestrator did not reach done state for live submit_pr flow.
```

The ticket remains in `tickets/in-progress/` — it is never moved to `tickets/done/`.

### Log Evidence

The orchestrator log shows the tick progresses through health check, architect, and manager phases normally, then stalls at the coding agent:

```
[DEBUG] tick 0: running coding agent
[DEBUG] executing ticket: tickets/in-progress/0001-live-submit-pr.md
[DEBUG] executeAssignedTicket: loadConfig
[DEBUG] executeAssignedTicket: reading ticket from plan worktree
[DEBUG] executeAssignedTicket: buildCodingAgentPrompt
[DEBUG] executeAssignedTicket: running coding agent
```

No further log output appears. The codex process itself hangs — it never produces output, never exits, and never calls `submit_pr`.

### Root Cause

Before the timeout/robustness changes, the `AgentRunRequest` in `executeAssignedTicket` had `noOutputTimeoutMs=0` and `hardTimeoutMs=0`, meaning **no timeout at all**. The codex process would block indefinitely.

### Fix Applied

Added `CodingAgentNoOutputTimeoutMs = 120_000` (2 min) and `CodingAgentHardTimeoutMs = 300_000` (5 min) constants, now set on the `AgentRunRequest` in `executeAssignedTicket`. The timeout machinery in `harness_codex.nim` (`runCodexAttempt`) already handles killing the process on timeout — it just was never being activated for coding agent runs.

### Remaining Issue: Timeout/Test Race

The test's `PositiveTimeoutMs = 300_000` (5 min) matches `CodingAgentHardTimeoutMs = 300_000`. This creates a race: the agent hard timeout and the test poll timeout fire at roughly the same moment, so the test may assert failure before the orchestrator has a chance to process the timeout result (record run notes, check submit_pr, etc.).

Possible fixes:
- Reduce `CodingAgentHardTimeoutMs` to 240_000 (4 min) to give the orchestrator ~60s of headroom to process results before the test gives up
- Increase the test's `PositiveTimeoutMs` to 360_000
- Both

### Why codex hangs in the first place

This is a separate question from the timeout fix. Possible reasons the live codex process hangs with no output:
- Model API latency or queuing (gpt-5.1-codex-mini under load)
- MCP server connection issues (the orchestrator HTTP server may not be fully ready when codex tries to connect)
- The prompt asks codex to call `submit_pr` via MCP tool, but codex may not reliably discover or invoke MCP tools
- Codex credential/auth issues causing a silent hang rather than an error

## IT-LIVE-04: SIGSEGV on shutdown (mummy HTTP server)

### Symptom

After IT-LIVE-04 completes successfully, the orchestrator daemon receives SIGINT during shutdown and crashes with:

```
Traceback (most recent call last)
.../orchestrator.nim(1909) runHttpServer
.../mcp_server_http.nim(241) serve
.../mummy.nim(1445) serve
.../mummy.nim(1247) loopForever
.../mummy.nim(1125) destroy
.../alloc.nim(1165) dealloc
.../alloc.nim(1052) rawDealloc
.../alloc.nim(815) addToSharedFreeList
SIGSEGV: Illegal storage access. (Attempt to read from nil?)
```

### Analysis

This is a use-after-free or double-free in the mummy HTTP server library during `destroy`. The crash happens in `addToSharedFreeList` inside Nim's allocator, which suggests a thread-safety issue in mummy's shutdown path — the server thread tries to deallocate memory that was already freed or belongs to another thread.

The test still passes (`[OK]`) because the SIGSEGV happens after the test assertions complete, during the `stopProcessWithSigint` cleanup.

### Possible Fixes

- This may be a bug in the mummy library's `close`/`destroy` sequence when called from a different thread than the one running `serve`
- The `httpServer.close()` call in `runOrchestratorLoop` happens on the main thread, while `serve` runs on `serverThread` — the close triggers `loopForever` to exit which triggers `destroy`
- May need to coordinate shutdown differently (e.g., set a flag and let the server thread close itself)
- Could be an ARC/thread interaction — mummy may not be fully ARC-safe for cross-thread close

## test_agent_runner: Pre-existing MCP config format mismatch

### Symptom

`test_agent_runner.nim` fails with:

```
Check failed: "mcp_servers.scriptorium.url=\"http://127.0.0.1:8097/mcp\"" in result.command
```

### Analysis

The test expects MCP server config to be passed as separate `-c` flags per field (`mcp_servers.scriptorium.url=...`, `.enabled=...`, `.required=...`), but the code now passes them as a single TOML table value:

```
-c mcp_servers.scriptorium={url = "http://127.0.0.1:8097/mcp", enabled = true, required = true}
```

This is a test expectation mismatch from a prior refactor of `buildMcpServersArgs` in `harness_codex.nim`. The test needs updating to match the new format. This is unrelated to the timeout/robustness work.
