# Integration And End-To-End Test Coverage

This document describes the integration and end-to-end coverage currently implemented under `tests/`.

## Test Entry Points

- `make test`: runs unit tests in `tests/test_*.nim`.
- `make integration-test`: runs integration tests in `tests/integration_*.nim`.

## Integration Coverage (`make integration-test`)

### `tests/integration_codex_prerequisites.nim`

Coverage:
- `IT-07 fails clearly when codex binary is missing`.
- `IT-07 fails clearly when API keys and OAuth auth are missing`.
- `IT-07 accepts OAuth auth file when API keys are missing`.

What it validates:
- The Codex harness fails fast with clear prerequisite errors.
- OAuth auth-file credentials are accepted when API keys are not set.

Notes:
- The success-path prerequisite test uses a temporary fake `codex` binary to validate auth gating behavior.

### `tests/integration_codex_harness.nim`

Coverage:
- `real codex exec one-shot smoke test`.

What it validates:
- `runCodex` can execute a real Codex one-shot run.
- Last-message and JSONL log artifacts are written.

Requires:
- `codex` binary in `PATH`.
- Either `OPENAI_API_KEY`/`CODEX_API_KEY` or a valid auth file (`CODEX_AUTH_FILE` or `~/.codex/auth.json`).

### `tests/integration_cli.nim`

Coverage:
- `status command prints ticket counts and active agent snapshot`.
- `worktrees command lists active ticket worktrees`.

What it validates:
- The compiled `scriptorium` CLI integrates correctly with a real fixture repository state.
- `status` and `worktrees` command output shape and ordering.

### `tests/integration_orchestrator_queue.nim`

Coverage:
- `IT-02 queue success moves ticket to done and merges ticket commit to master`.
- `IT-03 queue failure reopens ticket and appends failure note`.
- `IT-03b queue failure when integration-test fails reopens ticket`.
- `IT-04 single-flight queue processing keeps second item pending`.
- `IT-05 merge conflict during merge master into ticket reopens ticket`.
- `IT-08 recovery after partial queue transition converges without duplicate moves`.
- `IT-09 red master blocks assignment of open tickets`.
- `IT-10 global halt while red resumes after master health is restored`.
- `IT-11 integration-test failure on master blocks assignment of open tickets`.

What it validates:
- Queue success and failure transitions across `open`, `in-progress`, and `done`.
- Real git merge behavior, including conflicts.
- Merge-queue single-flight behavior and recovery/idempotence after partial state.
- Master health gates (`make test` and `make integration-test`) that block assignment when red.

### `tests/integration_mcp_submit_pr_live.nim`

Coverage:
- `IT-LIVE-01 real MCP HTTP tools/list and tools/call for submit_pr`.
- `IT-LIVE-02 real Codex calls submit_pr against live MCP HTTP server`.
- `IT-LIVE-03 codex mcp list confirms server is enabled and required`.

What it validates:
- Real HTTP JSON-RPC MCP transport for `submit_pr` (`tools/list` and `tools/call`).
- Real Codex tool-calling against a live MCP server.
- Codex MCP server configuration exposure (`enabled`/`required`) via `codex mcp list --json`.

Requires:
- `codex` binary and valid Codex auth for live Codex tests.

### `tests/integration_orchestrator_live_submit_pr.nim`

Coverage:
- `IT-LIVE-03 real daemon path completes ticket via live submit_pr`.
- `IT-LIVE-04 live daemon does not enqueue when submit_pr is missing`.

What it validates:
- Full live daemon execution (`scriptorium run`) from open ticket through coding run and merge queue to `done`.
- Negative live path where missing `submit_pr` leaves ticket unresolved and queue entry is not created.

Requires:
- `codex` binary and valid Codex auth.
- Network/API access for live model execution.

## End-To-End Coverage Currently Present

### Live end-to-end (integration suite)

- `tests/integration_orchestrator_live_submit_pr.nim`:
  - Positive full-cycle runtime (`IT-LIVE-03`).
  - Negative missing-submit path (`IT-LIVE-04`).
- `tests/integration_mcp_submit_pr_live.nim`:
  - Live Codex-to-MCP function call path (`IT-LIVE-02`).

### Deterministic end-to-end with fakes (`make test`)

The unit suite includes end-to-end workflow coverage with controlled runners/fakes:

- `tests/test_scriptorium.nim`:
  - `runOrchestratorForTicks drives spec to done in one bounded tick with mocked runners`.
  - `end-to-end happy path from spec to done`.
  - `orchestrator tick assigns and executes before merge queue processing`.

These tests exercise full orchestration transitions deterministically, while live integration tests exercise real Codex and MCP behavior.

## Live Test Prerequisites

To run the full integration suite (including live tests) without expected failures:

- `codex` must be installed and discoverable in `PATH`.
- Auth must be configured via one of:
  - `OPENAI_API_KEY`,
  - `CODEX_API_KEY`,
  - `CODEX_AUTH_FILE` (or `~/.codex/auth.json`).
- Network access to the configured model provider must be available.

## Model Guidance For Live Tool Calling

- `gpt-5.3-codex` is the default model for this repository's live MCP tool-calling integration tests.
- `gpt-5.1-codex-mini` is known bad for this repository's MCP tool-calling integration tests.

## Notes

- There is currently an integration test ID overlap: `IT-LIVE-03` appears in both:
  - `tests/integration_mcp_submit_pr_live.nim` (Codex MCP list coverage),
  - `tests/integration_orchestrator_live_submit_pr.nim` (live daemon E2E coverage).
- When discussing results, use file + test name, not test ID alone.
