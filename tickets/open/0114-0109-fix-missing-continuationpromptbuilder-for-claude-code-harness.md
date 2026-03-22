<!-- 0109-fix-claude-code-continuation-prompt-builder.md -->
# 0109 · Fix missing continuationPromptBuilder for Claude Code harness

**Area:** harness-backends

## Problem

In `src/scriptorium/agent_runner.nim`, the `runAgent` proc passes `continuationPromptBuilder` to the codex harness (line 137) and the typoi harness (line 205), but omits it when constructing the `ClaudeCodeRunRequest` (around line 156–176). This means Claude Code retries always fall back to the default continuation text instead of using the dynamic builder.

## Task

Add `continuationPromptBuilder: request.continuationPromptBuilder` to the `ClaudeCodeRunRequest` construction in `runAgent` at `src/scriptorium/agent_runner.nim`, alongside the existing `continuationPrompt` field (line 171).

Add a unit test in `tests/test_harness_claude_code.nim` (or an existing agent_runner test file if one exists) verifying that the builder is invoked during Claude Code retries.

## Acceptance

- `continuationPromptBuilder` is forwarded to `ClaudeCodeRunRequest` in `agent_runner.nim`.
- `make test` passes.
````

````markdown
<!-- 0110-add-audit-agent-role-to-config.md -->
# 0110 · Add audit agent role to config

**Area:** harness-backends

## Problem

The spec (Section 13) defines five agent roles: `architect`, `coding`, `manager`, `reviewer`, and `audit`. The `AgentConfigs` type in `src/scriptorium/config.nim` only has four fields — `audit` is missing. The `scriptorium.json` file also lacks an `agents.audit` entry.

## Task

1. Add an `audit` field to the `AgentConfigs` object in `src/scriptorium/config.nim`.
2. Add a `DefaultAuditModel` constant (use `"claude-haiku-4-5-20251001"` per the spec's low-cost audit intent).
3. Initialize the audit field in `defaultConfig()` using `defaultAgentConfig(DefaultAuditModel)`.
4. Add `mergeAgentConfig(result.agents.audit, parsed.agents.audit)` to `loadConfig()`.
5. Add an `"audit"` entry to `scriptorium.json` under `agents` (model: `"claude-haiku-4-5-20251001"`).
6. Add unit tests in `tests/test_scriptorium.nim` (or the appropriate config test file) verifying:
   - `defaultConfig().agents.audit.model` equals the expected default.
   - Loading a `scriptorium.json` with an audit override applies correctly.

Uses `jsony` for JSON parsing (already imported).

## Acceptance

- `AgentConfigs` has an `audit: AgentConfig` field.
- `loadConfig` merges audit config from `scriptorium.json`.
- `make test` passes.
````

````markdown
<!-- 0111-fix-harness-override-detection-in-merge.md -->
# 0111 · Fix mergeAgentConfig harness override detection

**Area:** harness-backends

## Problem

`mergeAgentConfig` in `src/scriptorium/config.nim` (lines 108–118) cannot distinguish between "user explicitly set `harness: claude-code`" and "harness field was absent from JSON" because jsony defaults the enum to its first value (`harnessClaudeCode`), which equals `DefaultHarness`. This means an explicit `"harness": "claude-code"` paired with a non-claude model (e.g. `"model": "gpt-4o"`) would be incorrectly overridden by `inferHarness()`.

## Task

1. Introduce a `ParsedAgentConfig` (or similar) intermediate type in `config.nim` where `harness` is a `string` (empty when absent from JSON).
2. Update `mergeAgentConfig` to accept the parsed harness as a string:
   - If the parsed harness string is non-empty, parse it to the `Harness` enum and set it (explicit override always wins).
   - If the parsed harness string is empty and a new model was provided, call `inferHarness()`.
   - If both are empty, keep the base default.
3. Update `loadConfig` to parse `scriptorium.json` into the intermediate type and pass it to the updated merge logic.
4. Add unit tests covering:
   - Explicit `"harness": "claude-code"` with `"model": "gpt-4o"` keeps claude-code (not inferred to codex).
   - Absent harness with `"model": "gpt-4o"` infers codex.
   - Absent harness with `"model": "claude-sonnet-4-6"` infers claude-code.

Uses `jsony` for JSON parsing (already imported).

## Acceptance

- Explicit harness in JSON always takes precedence over inference.
- Omitted harness triggers inference from model prefix.
- `make test` passes.
````

---

Three focused tickets:

- **0109** — One-line fix: forward `continuationPromptBuilder` to the Claude Code harness in `agent_runner.nim`.
- **0110** — Add the missing `audit` agent role to `AgentConfigs`, `defaultConfig`, `loadConfig`, and `scriptorium.json`.
- **0111** — Fix the harness merge logic so explicit `harness` overrides in JSON aren't clobbered by model-prefix inference.
