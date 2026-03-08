# Claude Code Harness Plan

This document describes the plan for adding Claude Code as a second agent harness
alongside Codex, redesigning the config to support flexible harness assignment, and
adding env var overrides for integration/e2e test permutations.

## Background

Scriptorium currently wraps OpenAI Codex as a subprocess harness (`harness_codex.nim`).
The `agent_runner.nim` module dispatches to it, and `config.nim` infers the harness from
the model name prefix (`claude-*` -> claude-code, `codex-*`/`gpt-*` -> codex, else typoi).

This plan adds a real Claude Code harness, removes the model-prefix inference from
production config, and prepares the architecture for a future typoi harness.

## 1. Config Redesign

### Current `scriptorium.json`

```json
{
  "models": {
    "architect": "claude-opus-4-6",
    "coding": "gpt-5.1-codex-mini",
    "manager": "gpt-5.1-codex-mini"
  },
  "reasoningEffort": {
    "architect": "high",
    "coding": "",
    "manager": ""
  },
  "endpoints": { "local": "" }
}
```

### Proposed `scriptorium.json`

Each role explicitly declares its harness, model, and reasoning effort together.
No inference from model name in production code.

```json
{
  "agents": {
    "architect": {
      "harness": "claude-code",
      "model": "claude-opus-4-6",
      "reasoningEffort": "high"
    },
    "coding": {
      "harness": "codex",
      "model": "gpt-5.1-codex-mini",
      "reasoningEffort": ""
    },
    "manager": {
      "harness": "codex",
      "model": "gpt-5.1-codex-mini",
      "reasoningEffort": ""
    }
  },
  "endpoints": { "local": "" },
  "logLevel": ""
}
```

### Changes to `config.nim`

- Replace `Models` and `ReasoningEffort` types with a single `AgentConfig` object:
  ```nim
  AgentConfig* = object
    harness*: Harness
    model*: string
    reasoningEffort*: string
  ```
- Replace `Config.models` and `Config.reasoningEffort` with:
  ```nim
  AgentConfigs* = object
    architect*: AgentConfig
    coding*: AgentConfig
    manager*: AgentConfig

  Config* = object
    agents*: AgentConfigs
    endpoints*: Endpoints
    logLevel*: string
  ```
- **Delete the `harness(model)` proc** from production code. Harness is now explicit in
  config. A lightweight `inferHarness(model)` helper may remain in test support code only,
  as a convenience default when env vars are partially set.
- `loadConfig` merges parsed values over defaults as before, using the new shape.

## 2. Claude Code Harness Module

### CLI comparison: Codex vs Claude Code

| Concern | Codex | Claude Code |
|---|---|---|
| Non-interactive mode | `codex exec --json -` (stdin prompt, JSONL stdout) | `claude --print --output-format stream-json` (stdin pipe, stream-json stdout) |
| Sandbox bypass | `--dangerously-bypass-approvals-and-sandbox` | `--dangerously-skip-permissions` |
| Model selection | `--model <model>` | `--model <model>` |
| Working dir | `--cd <dir>` | Spawn process with `workingDir` (uses cwd) |
| MCP config | `-c mcp_servers.foo={...}` inline TOML | `--mcp-config '<json>'` |
| Reasoning effort | `-c model_reasoning_effort="high"` | `--effort low\|medium\|high` |
| Output format | JSONL with `type` field | stream-json with `type` field (different envelope shapes) |
| Last message capture | `--output-last-message <path>` | No built-in flag; accumulate message events from stream |

### Claude Code `stream-json` envelope format

Captured from Claude Code v2.1.71. Requires `--verbose` with `--output-format stream-json`.
Full samples in `docs/claude-code-stream-json-sample.jsonl`.

Top-level dispatch is on the `type` field. Six event shapes observed:

| `type` | Content block `type` | Scriptorium event kind | Key fields |
|---|---|---|---|
| `system` (subtype `init`) | — | `status` | `session_id`, `model`, `tools`, `mcp_servers`, `claude_code_version` |
| `assistant` | `thinking` | `reasoning` | `message.content[].thinking` |
| `assistant` | `tool_use` | `tool` | `message.content[].name`, `message.content[].input` |
| `user` | `tool_result` | `tool` | `message.content[].tool_use_id`, `tool_use_result.stdout` |
| `assistant` | `text` | `message` | `message.content[].text` |
| `result` (subtype `success`/`error`) | — | `status` | `is_error`, `result`, `stop_reason`, `total_cost_usd`, `num_turns` |

Each `assistant` event wraps the full Anthropic API message object in `.message`.
The `message.content` array contains typed content blocks — a single event may carry
one block (text, thinking, or tool_use). The last `text` block in the stream before
the `result` event is the final assistant message.

### New file: `src/scriptorium/harness_claude_code.nim`

Mirrors the structure of `harness_codex.nim`:

**Types:**
- `ClaudeCodeRunRequest` — prompt, workingDir, model, reasoningEffort, mcpEndpoint, ticketId, attempt, binary, logRoot, timeouts, heartbeat, maxAttempts, continuationPrompt, onEvent callback.
- `ClaudeCodeRunResult` — command, exitCode, attempt, attemptCount, stdout, logFile, lastMessageFile, lastMessage, timeoutKind.
- `ClaudeCodeStreamEvent` / event kinds — or reuse the shared `CodexStreamEventKind` pattern with Claude-specific naming.

**Key procs:**
- `buildClaudeCodeExecArgs*(request, lastMessagePath): seq[string]` — builds:
  - `--print --output-format stream-json`
  - `--dangerously-skip-permissions`
  - `--model <model>`
  - `--effort <level>` (when set)
  - `--mcp-config <json>` (when MCP endpoint configured)
- `buildMcpConfigJson*(endpoint: string): string` — generates Claude Code MCP server JSON.
- `buildClaudeCodeStreamEvent(line: string): ClaudeCodeStreamEvent` — parses one stream-json line into a normalized event.
- `runClaudeCodeAttempt(request, prompt, attemptValue): ClaudeCodeRunResult` — spawns `claude`, pipes prompt via stdin, polls stdout with `waitForReadable`, enforces timeouts, logs to JSONL.
- `runClaudeCode*(request: ClaudeCodeRunRequest): ClaudeCodeRunResult` — outer loop with bounded retries and continuation prompts.

**Last message handling:** Claude Code has no `--output-last-message` flag. Accumulate
`message`-type events from the stream during the run. After the process exits, write the
final accumulated message text to the last-message file path ourselves.

**Subprocess lifecycle:** Same pattern as Codex — `startProcess` with `poStdErrToStdOut`,
pipe prompt to stdin then close it, poll with `waitForReadable` / `readOutputChunk`,
no-output timeout, hard timeout, heartbeat emission, JSONL log file.

### Prompt templates

The existing `codex_retry_continuation.md` template is generic (references attempt number,
exit code, timeout kind, summary tail). Reuse it for Claude Code initially. If Claude Code
needs different retry framing later, add `claude_code_retry_continuation.md`.

## 3. Agent Runner Changes

### `agent_runner.nim`

- Rename `codexBinary` on `AgentRunRequest` to a generic `binary` field. Each harness
  module has its own default constant (`"codex"`, `"claude"`) so this field is only needed
  for overrides and testing.
- Add `harness*: Harness` field to `AgentRunRequest`. The caller (orchestrator) reads
  this from `cfg.agents.<role>.harness` instead of inferring it.
- Add the `harnessClaudeCode` case to the `runAgent` dispatch:
  ```nim
  of harnessClaudeCode:
    let claudeResult = runClaudeCode(ClaudeCodeRunRequest(...))
    result = AgentRunResult(backend: backend, ...)
  ```
- Add `mapClaudeCodeEvent` proc analogous to `mapCodexEvent`.

## 4. Orchestrator Changes

Mechanical replacement across ~15 call sites in `orchestrator.nim`:

| Before | After |
|---|---|
| `cfg.models.architect` | `cfg.agents.architect.model` |
| `cfg.models.coding` | `cfg.agents.coding.model` |
| `cfg.models.manager` | `cfg.agents.manager.model` |
| `cfg.reasoningEffort.architect` | `cfg.agents.architect.reasoningEffort` |
| `cfg.reasoningEffort.coding` | `cfg.agents.coding.reasoningEffort` |
| `cfg.reasoningEffort.manager` | `cfg.agents.manager.reasoningEffort` |

Additionally, pass `cfg.agents.<role>.harness` into each `AgentRunRequest`.

## 5. Test Env Vars for Harness/Model Permutations

### Proposed env vars

| Env var | Default | Purpose |
|---|---|---|
| `SCRIPTORIUM_TEST_MODEL` | `gpt-5.4` | Model for all three roles |
| `SCRIPTORIUM_TEST_HARNESS` | inferred from model | Harness for all three roles |
| `SCRIPTORIUM_TEST_CODING_MODEL` | falls back to `_TEST_MODEL` | Override model for coding role only |
| `SCRIPTORIUM_TEST_CODING_HARNESS` | falls back to `_TEST_HARNESS` | Override harness for coding role only |

The old `CODEX_INTEGRATION_MODEL` env var is removed (breaking changes are acceptable).

### Changes to `live_integration_support.nim`

```nim
proc integrationModel*(): string =
  ## Return the test model from env, or the default.
  result = getEnv("SCRIPTORIUM_TEST_MODEL", DefaultIntegrationModel)

proc integrationHarness*(): Harness =
  ## Return the test harness from env, or infer from model.
  let envVal = getEnv("SCRIPTORIUM_TEST_HARNESS", "").strip()
  if envVal.len > 0:
    result = parseEnum[Harness](envVal)
  else:
    result = inferHarness(integrationModel())
```

The `inferHarness` helper lives in test support only (not production config). It uses the
same model-prefix heuristic that `harness()` uses today, purely as a convenience default
so you don't have to set both env vars every time.

`writeLiveConfig` builds `AgentConfig` objects using these helpers.

### Auth detection

`hasCodexAuth` is extended to also check `ANTHROPIC_API_KEY` when the test harness is
`claude-code`. Rename to `hasAgentAuth` or similar.

### Makefile

```makefile
# Default: codex + gpt-5.4 (current behavior)
integration-test:
	@found=0; \
	for f in tests/integration_*.nim; do ...

# Convenience target for claude-code
integration-test-claude:
	SCRIPTORIUM_TEST_MODEL=claude-sonnet-4-6 \
	SCRIPTORIUM_TEST_HARNESS=claude-code \
	$(MAKE) integration-test

# Convenience target for e2e with claude-code
e2e-test-claude:
	SCRIPTORIUM_TEST_MODEL=claude-sonnet-4-6 \
	SCRIPTORIUM_TEST_HARNESS=claude-code \
	$(MAKE) e2e-test
```

Running with custom permutations from the command line:
```bash
SCRIPTORIUM_TEST_MODEL=claude-opus-4-6 SCRIPTORIUM_TEST_HARNESS=claude-code make integration-test
```

## 6. Tests

### Unit tests

- **`tests/test_harness_claude_code.nim`** — arg building, MCP config JSON generation,
  stream event parsing. Same pattern as `test_harness_codex.nim`.
- **Update `tests/test_scriptorium.nim`** — config loading tests use the new `agents`
  shape. Remove `harness()` inference tests (or move to test support tests).
- **Update `tests/test_agent_runner.nim`** — pass harness explicitly in requests.

### Integration tests

- **`tests/integration_claude_code_harness.nim`** — live test that spawns
  `claude --print --output-format stream-json` and verifies streaming, exit code, and
  log output.

## 7. Future: typoi

The pattern is established: each harness is a self-contained module (`harness_*.nim`) with
its own types and subprocess lifecycle, mapping into the shared `AgentStreamEvent` /
`AgentRunResult` types in `agent_runner.nim`.

When typoi arrives:
1. Add `src/scriptorium/harness_typoi.nim` following the same pattern.
2. Add a `harnessTypoi` case in `agent_runner.nim`.
3. Users configure it in `scriptorium.json`:
   ```json
   "coding": {
     "harness": "typoi",
     "model": "local/qwen3.5-35b-a3b",
     "reasoningEffort": ""
   }
   ```

No changes needed in config or orchestrator beyond the new dispatch case.

## 8. Implementation Order

1. **Capture Claude Code `stream-json` output** — run
   `claude --print --output-format stream-json -p "say hello"` and save the raw output
   to understand the actual JSON envelope shapes.
2. **Config redesign** — update `config.nim`, default config, and all tests. This is the
   breaking change and touches the most files, so do it first.
3. **Create `harness_claude_code.nim`** — arg building, stream parsing, subprocess
   lifecycle.
4. **Wire into `agent_runner.nim`** — generic `binary` field, `harness` field, new
   dispatch case.
5. **Update `orchestrator.nim`** — mechanical replacement of `cfg.models.X` to
   `cfg.agents.X.model` etc.
6. **Test env vars** — update `live_integration_support.nim`, add `inferHarness` helper,
   rename auth check, add Makefile targets.
7. **Write new tests** — `test_harness_claude_code.nim`,
   `integration_claude_code_harness.nim`.
8. **Update existing tests** — config shape, harness dispatch, integration support.
9. **`make test`** to verify everything passes.
