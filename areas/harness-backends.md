# Harness Routing And Agent Backends

Covers role-based agent configuration, model-prefix harness inference, and backend implementations.

## Scope

- Role-based config in `scriptorium.json` under `agents.architect`, `agents.coding`, `agents.manager`.
- Each role supports: `harness`, `model`, `reasoningEffort`.
- Model-prefix harness inference:
  - `claude-*` -> `claude-code`
  - `codex-*` and `gpt-*` -> `codex`
  - All other models -> `typoi`
- Explicit `harness` override supported per role.
- Current defaults (test-focused): model `codex-fake-unit-test-model`, harness `codex`.
- Implementation state: `codex` implemented, `claude-code` implemented, `typoi` routed but fails fast.
- Codex harness:
  - Command: `codex exec --json ... --output-last-message ...`
  - `--dangerously-bypass-approvals-and-sandbox`, optional `--skip-git-repo-check`.
  - MCP server injection via `-c` config args.
  - JSONL run logs, parsed stream events (heartbeat, reasoning, tool, status, message).
  - Last-message capture, no-output and hard-timeout handling.
  - Bounded retry with continuation prompt.
  - Reasoning-effort normalization for supported codex models.
- Claude Code harness:
  - Command: `claude --print --output-format stream-json --verbose`
  - `--dangerously-skip-permissions`, optional MCP injection via `--mcp-config`.
  - Stream-json event parsing (heartbeat, reasoning, tool, status, message).
  - Last-message extraction, no-output and hard-timeout handling.
  - Bounded retry with continuation prompt.
  - Reasoning-effort normalization for supported Claude Code values.

## Spec References

- Section 6: Harness Routing And Agent Backends.
