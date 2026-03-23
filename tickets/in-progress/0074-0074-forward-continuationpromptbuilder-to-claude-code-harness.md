# 0074 Forward continuationPromptBuilder to Claude Code harness

**Area:** compaction-context

## Problem

In `src/scriptorium/agent_runner.nim`, the `continuationPromptBuilder` is forwarded to the Codex and Typoi harnesses but **not** to the Claude Code harness. Around line 171-172, only `continuationPrompt` (the static string) is passed to `ClaudeCodeRunRequest`, while `continuationPromptBuilder` is omitted.

## Task

In `src/scriptorium/agent_runner.nim`, update the Claude Code `ClaudeCodeRunRequest` construction (around line 171) to also forward `continuationPromptBuilder: request.continuationPromptBuilder`, matching how Codex (line 137) and Typoi (line 205) already do it.

The `ClaudeCodeRunRequest` type in `src/scriptorium/harness_claude_code.nim` already has a `continuationPromptBuilder` field (line 57), and `buildContinuationPrompt` in that file (line 414-443) already checks for a non-nil builder. So the only change needed is in `agent_runner.nim`.

## Verification

- `make test` passes.
- Confirm the builder field is forwarded by reading the constructed request in agent_runner.nim.
````

````markdown
# 0075 Implement AGENTS.md re-injection continuation prompt builder

**Area:** compaction-context

**Depends:** 0074

## Problem

When an agent hits a timeout or retry, the continuation prompt currently uses a generic default message ("Continue from the previous attempt and complete the ticket"). It does not re-inject project rules from `AGENTS.md`, so after context compaction the agent loses awareness of project conventions.

## Task

Create a `ContinuationPromptBuilder` implementation that reads `AGENTS.md` from the agent's working directory and returns a condensed version of the critical rules as continuation text.

1. In a new file `src/scriptorium/continuation_builder.nim`, create a proc `buildAgentsReinjectPrompt*(workingDir: string): string` that:
   - Reads `AGENTS.md` from `workingDir` (fall back to the repo root if not found in workingDir).
   - If the file exceeds 4000 characters, truncate it (keep the first 4000 chars and append a note that rules were truncated).
   - Wraps the content in a template that says: "The following project rules from AGENTS.md must be followed:" followed by the content, then the default continuation instruction ("Continue from the previous attempt and complete the ticket. When done, call the `submit_pr` MCP tool with a summary.").
   - If `AGENTS.md` cannot be found, fall back to the default continuation text only.

2. The proc signature must match `ContinuationPromptBuilder = proc(workingDir: string): string` from `src/scriptorium/common.nim`.

## Libraries

- Use `std/os` for path operations and `std/strutils` for string manipulation. No external dependencies needed.

## Verification

- `make test` passes.
- Add a unit test in `tests/test_continuation_builder.nim` that verifies:
  - When AGENTS.md exists, the builder output contains the rules content.
  - When AGENTS.md is missing, the builder returns the default continuation text.
  - When AGENTS.md is very large, the output is truncated.
````

````markdown
# 0076 Wire continuation prompt builder into orchestrator agent launches

**Area:** compaction-context

**Depends:** 0074, 0075

## Problem

Even after the builder is implemented (0075) and the forwarding gap is fixed (0074), no code actually passes `buildAgentsReinjectPrompt` as the `continuationPromptBuilder` when launching coding agents.

## Task

In the orchestrator code that constructs `AgentRunRequest` for coding agents, set `continuationPromptBuilder` to `buildAgentsReinjectPrompt` from `src/scriptorium/continuation_builder.nim`.

1. Find where `AgentRunRequest` is constructed for coding agent launches (likely in `src/scriptorium/orchestrator.nim` or the tick/dispatch logic).
2. Import `continuation_builder` and assign `continuationPromptBuilder: buildAgentsReinjectPrompt`.
3. This should apply to all harness types (Claude Code, Codex, Typoi) since all three support the builder.

## Verification

- `make test` passes.
- Trace the code path: `AgentRunRequest` → `agent_runner` → harness-specific request → `buildContinuationPrompt` should now use the AGENTS.md builder for all coding agents.
````

````markdown
# 0077 Create CLAUDE.md with critical project rules for compaction resilience

**Area:** compaction-context

## Problem

Claude Code reloads `CLAUDE.md` (or `.claude/` config files) after context compaction. Currently no `CLAUDE.md` exists in the project, so compacted Claude Code agents lose all project conventions.

## Task

Create a `CLAUDE.md` file at the repository root containing the most critical subset of rules from `AGENTS.md` that agents must follow even after compaction. This file should be concise (under 80 lines) and include only the rules that, if violated, cause the most damage:

1. **Agent completion protocol**: Must call `submit_pr` MCP tool when done.
2. **MCP transport**: MCPort uses plain JSON-RPC over HTTP POST, no SSE.
3. **Nim coding conventions**: Import style (bracket syntax, ordering), no forward declarations, doc comments, variable naming (PascalCase constants, camelCase vars), grouped const/let/var blocks.
4. **Programming principles**: No try/catch unless necessary, never mask errors, no boolean success/error returns, no stdout scanning.
5. **Test conventions**: Unit vs integration test separation, no mocks in integration tests.

Add a note at the top: "This file is auto-loaded by Claude Code after context compaction. See AGENTS.md for full project rules."

## Verification

- The file exists at `/workspace/CLAUDE.md`.
- Content is under 80 lines and covers the critical rules listed above.
- `make test` still passes (no code changes).
````

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0074-0074-forward-continuationpromptbuilder-to-claude-code-harness

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Four tickets but mostly straightforward: 0074 is a trivial one-line fix, 0075 is a small new file with simple file-reading logic plus a test, 0076 is a one-line wiring change, and 0077 is a static markdown file creation; the multi-file scope and test writing push it to medium.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0074/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0074/attempt-01.last_message.txt\n
### Agent Last Message
```text
All four tickets implemented and submitted:

- **0074**: Added `continuationPromptBuilder: request.continuationPromptBuilder` to the `ClaudeCodeRunRequest` in `agent_runner.nim:172`
- **0075**: Created `src/scriptorium/continuation_builder.nim` with `buildAgentsReinjectPrompt` that reads and re-injects AGENTS.md rules, plus unit tests in `tests/test_continuation_builder.nim`
- **0076**: Imported `continuation_builder` in `coding_agent.nim` and wired `continuationPromptBuilder: buildAgentsReinjectPrompt` into the coding agent's `AgentRunRequest`
- **0077**: Created `CLAUDE.md` (35 lines) with critical project rules for compaction resilience
```

### Agent Stdout Tail
```text
im` with `buildAgentsReinjectPrompt` that reads and re-injects AGENTS.md rules, plus unit tests in `tests/test_continuation_builder.nim`\n- **0076**: Imported `continuation_builder` in `coding_agent.nim` and wired `continuationPromptBuilder: buildAgentsReinjectPrompt` into the coding agent's `AgentRunRequest`\n- **0077**: Created `CLAUDE.md` (35 lines) with critical project rules for compaction resilience","stop_reason":"end_turn","session_id":"e74480f9-219e-4870-8167-e3c99818f49d","total_cost_usd":0.83525275,"usage":{"input_tokens":531,"cache_creation_input_tokens":44497,"cache_read_input_tokens":753583,"output_tokens":7108,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":44497},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":531,"outputTokens":7108,"cacheReadInputTokens":753583,"cacheCreationInputTokens":44497,"webSearchRequests":0,"costUSD":0.83525275,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"734b397f-9b59-4d12-9a69-1a27596353b6"}
```
