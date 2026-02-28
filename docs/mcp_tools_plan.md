# Plan: Replace stdout-scanning `submit_pr` with MCP tool call

## Status Update

Core implementation in this plan is now in place:
- orchestrator registers MCP `submit_pr`,
- codex harness receives dynamic `mcp_servers`,
- stdout scanning path is removed from ticket completion handling.

Remaining gap: this plan still needs strict live integration coverage to prove
real runtime behavior (real MCP HTTP transport + real codex tool call + real
orchestrator daemon flow). Unit tests and fixture-driven tests are not enough
to claim end-to-end MCP integration.

## Context

The coding agent signals completion by emitting the literal string `submit_pr("summary")` in its output. The orchestrator then string-scans `agentResult.lastMessage` and `agentResult.stdout` to find this marker and enqueue a merge request. This is fragile, undocumented to the agent (the coding agent prompt never mentions `submit_pr`), and bypasses the MCP tool infrastructure that already exists. The MCP server (`createOrchestratorServer`) is running but has zero tools registered. The codex harness passes `mcp_servers={}` — agents see no MCP tools at all.

## Design

### Register `submit_pr` as an MCP tool on the orchestrator server

In `createOrchestratorServer`, register a `submit_pr` tool using mcport's `registerTool` API. The tool accepts one argument: `summary` (string). The handler stores the summary in module-level shared state (a `Lock`-protected var). This is safe because only one coding agent runs at a time (the main loop is synchronous).

```nim
var
  submitPrLock: Lock
  submitPrSummary: string

proc createOrchestratorServer*(): HttpMcpServer =
  let server = newMcpServer(OrchestratorServerName, OrchestratorServerVersion)
  let tool = McpTool(
    name: "submit_pr",
    description: "Signal that ticket work is complete and ready for merge queue",
    inputSchema: %*{
      "type": "object",
      "properties": {
        "summary": {"type": "string", "description": "Short summary of changes"}
      },
      "required": ["summary"]
    }
  )
  server.registerTool(tool, proc(arguments: JsonNode): JsonNode =
    withLock submitPrLock:
      submitPrSummary = arguments["summary"].getStr()
    %*"Merge request enqueued."
  )
  result = newHttpMcpServer(server, logEnabled = false)
```

Add helper procs to read/clear the shared state:

```nim
proc consumeSubmitPrSummary*(): string =
  withLock submitPrLock:
    result = submitPrSummary
    submitPrSummary = ""
```

### Thread the MCP endpoint URL to the codex harness

1. Add `mcpEndpoint*: string` field to `AgentRunRequest` (agent_runner.nim)
2. Add `mcpEndpoint*: string` field to `CodexRunRequest` (harness_codex.nim)
3. In `runAgent`, copy `request.mcpEndpoint` → `CodexRunRequest.mcpEndpoint`
4. In `buildCodexExecArgs`, replace the hardcoded `DefaultCodexMcpServers` constant:
   - If `mcpEndpoint` is non-empty: `mcp_servers={scriptorium={type="http",url="<endpoint>/mcp"}}`
   - If empty: `mcp_servers={}` (preserves backward compat for tests)
5. In `executeAssignedTicket`, set `request.mcpEndpoint = cfg.endpoints.local` when building `AgentRunRequest`

### Replace stdout scanning with MCP tool result

In `executeAssignedTicket`, after the agent run completes:
1. Call `consumeSubmitPrSummary()` to get the summary (if the tool was called)
2. If non-empty, call `enqueueMergeRequest` as before
3. Remove `extractSubmitPrSummary` and all stdout-scanning logic

### Update coding agent prompt

`src/scriptorium/prompts/coding_agent.md` — add completion instructions:

```
When your work is complete and all changes are committed, call the `submit_pr`
MCP tool with a short summary of what you did. This signals the orchestrator
to enqueue your changes for merge. Do not skip this step.
```

### Update retry continuation prompt

`src/scriptorium/prompts/codex_retry_default_continuation.md` — remind the agent:

```
Continue from the previous attempt and complete the ticket.
When done, call the `submit_pr` MCP tool with a summary.
```

### Update documentation

1. **`AGENTS.md`** — Add a section on agent completion protocol: coding agents must call the `submit_pr` MCP tool when done.
2. **`README.md`** — Update line 25 from `signals completion via submit_pr("...")` to describe MCP tool calling.
3. **`src/scriptorium/prompts/README.md`** — Document the `submit_pr` MCP tool as a cross-cutting concern.

## Files modified

| File | Change |
|------|--------|
| `src/scriptorium/orchestrator.nim` | Register `submit_pr` tool, add shared state + lock, replace stdout scanning in `executeAssignedTicket` with `consumeSubmitPrSummary()`, remove `extractSubmitPrSummary` |
| `src/scriptorium/agent_runner.nim` | Add `mcpEndpoint` field to `AgentRunRequest`, thread it to `CodexRunRequest` |
| `src/scriptorium/harness_codex.nim` | Add `mcpEndpoint` field to `CodexRunRequest`, build dynamic `mcp_servers=` TOML in `buildCodexExecArgs` |
| `src/scriptorium/prompts/coding_agent.md` | Add `submit_pr` MCP tool instructions |
| `src/scriptorium/prompts/codex_retry_default_continuation.md` | Remind agent to call `submit_pr` |
| `src/scriptorium/prompts/README.md` | Document `submit_pr` tool |
| `AGENTS.md` | Add agent completion protocol section |
| `README.md` | Update completion mechanism description |
| `tests/test_scriptorium.nim` | Update tests: fake runners no longer need `submit_pr(...)` in lastMessage; test `consumeSubmitPrSummary`; update `executeAssignedTicket` tests |
| `tests/test_harness_codex.nim` | Test dynamic `mcp_servers=` arg building |

## MCPort API Reference (for implementation)

The mcport library (`McpServer`) exposes:

```nim
# Tool type
McpTool* = object
  name*: string
  description*: string
  inputSchema*: JsonNode
  # optional: title, outputSchema, annotations

# Simple handler — takes JSON args, returns JSON
ToolHandler* = proc(arguments: JsonNode): JsonNode {.gcsafe.}

# Registration
proc registerTool*(server: McpServer, tool: McpTool, handler: ToolHandler)
```

Example from mcport source:

```nim
let tool = McpTool(
  name: "secret_fetcher",
  description: "Delivers a secret leet greeting",
  inputSchema: %*{ "type": "object", "properties": { ... } }
)
mcpServer.registerTool(tool, proc(arguments: JsonNode): JsonNode =
  %*("Hello!")
)
```

## Verification

1. `make test` passes
2. `make integration-test` passes
3. Verify `extractSubmitPrSummary` is fully removed (grep confirms no references)
4. Verify `buildCodexExecArgs` with an mcpEndpoint produces correct TOML in mcp_servers flag
5. Verify `createOrchestratorServer` registers the `submit_pr` tool (unit test calls `consumeSubmitPrSummary`)

## Required Follow-Up Verification (Mandatory)

1. Add integration test that starts a real MCP HTTP server and uses HTTP JSON-RPC `/mcp` calls to validate `tools/list` and `tools/call` for `submit_pr`.
2. Add integration test that runs real codex with configured `mcpEndpoint` and verifies codex performs a real `submit_pr` tool call captured by `consumeSubmitPrSummary()`.
3. Add integration test that runs real `scriptorium run` daemon path (not bounded tick helper) and verifies live tool-calling drives queue enqueue and ticket completion.
4. Keep these tests always-on in `make integration-test`; do not use fake codex binaries, mock MCP handlers, or conditional skip paths for these core integration boundaries.
