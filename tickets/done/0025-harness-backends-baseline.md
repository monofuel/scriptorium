# Harness Routing And Agent Backends Baseline

**Area:** harness-backends
**Status:** done

## Summary

Role-based agent configuration, model-prefix harness inference, and both backend implementations are fully implemented and tested.

## What Exists

- Role-based config in `scriptorium.json` under `agents.architect`, `agents.coding`, `agents.manager`.
- Each role supports `harness`, `model`, `reasoningEffort`.
- Model-prefix harness inference in `config.nim` `inferHarness()`:
  - `claude-*` → `claude-code`
  - `codex-*` and `gpt-*` → `codex`
  - All other models → `typoi`
- Explicit `harness` override supported per role.
- Current defaults: model `codex-fake-unit-test-model`, harness `codex`.
- `typoi` routed but fails fast as unimplemented.
- Codex harness (`harness_codex.nim`):
  - `codex exec --json ... --output-last-message ...`
  - `--dangerously-bypass-approvals-and-sandbox`, optional `--skip-git-repo-check`
  - MCP injection via `-c mcp_servers.scriptorium={...}` config args
  - JSONL run logs with parsed stream events (heartbeat, reasoning, tool, status, message)
  - Last-message capture, no-output and hard-timeout handling
  - Bounded retry with continuation prompt
  - Reasoning-effort normalization for supported codex models
- Claude Code harness (`harness_claude_code.nim`):
  - `claude --print --output-format stream-json --verbose`
  - `--dangerously-skip-permissions`, optional MCP injection via `--mcp-config`
  - Stream-json event parsing
  - Last-message extraction, no-output and hard-timeout handling
  - Bounded retry with continuation prompt
  - Reasoning-effort normalization for supported Claude Code values
- Tests: `test_harness_codex.nim`, `test_harness_claude_code.nim`, `integration_codex_harness.nim`, `integration_claude_code_harness.nim`.
