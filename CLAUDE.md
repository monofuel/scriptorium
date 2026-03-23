# This file is auto-loaded by Claude Code after context compaction. See AGENTS.md for full project rules.

## Agent completion protocol

- Coding agents must call the `submit_pr` MCP tool when ticket work is complete.
- Include a short `summary` argument describing the completed changes.
- Orchestrator merge-queue enqueueing uses MCP tool state, not stdout parsing.

## MCP transport

- MCPort uses plain JSON-RPC over HTTP POST (Streamable HTTP). It does NOT support SSE.
- Do NOT set `"type": "sse"` when configuring MCP server connections.

## Nim coding conventions

- One `import` block. Use bracket syntax. Order: std/ then libraries then local.
- No forward declarations. Move proc definitions above call sites.
- Doc comments (##) on every proc. Comments are complete sentences with punctuation.
- Constants use PascalCase. Variables use camelCase.
- Group `const`, `let`, and `var` into blocks. Prefer const > let > var.

## Programming principles

- Do not use try/catch unless absolutely necessary. Never mask errors with `catch: discard`.
- Let errors bubble up. Fail fast for easy debugging.
- Never use booleans for success/error. Return nothing on success; raise on failure.
- Never rely on stdout scanning. Use proper MCP tools for agent interaction.

## Test conventions

- Unit tests (`tests/test_*.nim`): test in isolation. Mocks and fakes belong here.
- Integration tests (`tests/integration_*.nim`): test real components together. No mocks.
- Do not put mocked tests in integration files. Do not call real services in unit tests.

## Format strings

- Use `&` for format strings, not `fmt`. Do not call functions inside format strings.
- Assign to variables first, then interpolate.
