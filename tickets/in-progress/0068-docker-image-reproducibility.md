# Docker Image Reproducibility

**Area:** docker-reproducibility

Pin all external dependencies in the Dockerfile for build reproducibility (V8, §33).

## Requirements

### Base Image Pinning
- Change `FROM gitea.solution-nine.monofuel.dev/monolab/monolab/monolab-nim:latest` to use a specific tag:
  - `FROM gitea.solution-nine.monofuel.dev/monolab/monolab-nim:2.2.4`
- Note: the current `FROM` path has a double `monolab/monolab` which may also need correcting.

### NPM Package Version Pinning
- Pin `@openai/codex` and `@anthropic-ai/claude-code` to explicit versions:
  - `RUN npm install --global @openai/codex@<version> @anthropic-ai/claude-code@<version>`
- Use current latest stable versions at time of implementation.

### Version Traceability
- Update `scripts/entrypoint.sh` to print installed versions of pinned dependencies on startup:
  - Base image tag (from a build arg or label).
  - `codex --version` output.
  - `claude --version` output.
- This allows operators to confirm which versions are running.

### Update Mechanism
- Add a `make check-updates` Makefile target that checks for available updates to pinned npm packages.
- Use `npm outdated --global` or `npm view <pkg> version` to report newer versions.
- Advisory only — does not automatically update the Dockerfile.

## Acceptance Criteria

- Dockerfile uses pinned base image tag (not `:latest`).
- npm packages installed with explicit version specifiers.
- Entrypoint logs version information on startup.
- `make check-updates` reports whether newer versions exist.
- Docker image builds successfully with pinned versions.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0068-docker-image-reproducibility

## Prediction
- predicted_difficulty: easy
- predicted_duration_minutes: 12
- reasoning: Straightforward edits to three existing files (Dockerfile, entrypoint.sh, Makefile) with no complex logic — just pinning versions, adding echo statements, and a simple shell target.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0068-docker-image-reproducibility/.scriptorium/logs/0068/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0068-docker-image-reproducibility/.scriptorium/logs/0068/attempt-01.last_message.txt\n
### Agent Last Message
```text
The `submit_pr` MCP tool is not available in this environment. All my changes are committed and ready. Here's a summary of what was done:

**Changes committed** (fa6092b on `scriptorium/ticket-0068`):

1. **Dockerfile** - Pinned base image to `monolab-nim:2.2.4` (also fixed the double `monolab/monolab` path), pinned `@openai/codex@0.114.0` and `@anthropic-ai/claude-code@2.1.76` via build ARGs, and exposed `MONOLAB_NIM_TAG` as an ENV for runtime traceability.

2. **scripts/entrypoint.sh** - Added version logging on startup: base image tag, codex version, and claude-code version.

3. **Makefile** - Added `check-updates` target that compares pinned versions against latest npm registry versions and reports if updates are available.

I'm unable to call `submit_pr` as the MCP tool isn't configured in this environment. The commit is ready on branch `scriptorium/ticket-0068` for the orchestrator to pick up.
```

### Agent Stdout Tail
```text
on logging on startup: base image tag, codex version, and claude-code version.\n\n3. **Makefile** - Added `check-updates` target that compares pinned versions against latest npm registry versions and reports if updates are available.\n\nI'm unable to call `submit_pr` as the MCP tool isn't configured in this environment. The commit is ready on branch `scriptorium/ticket-0068` for the orchestrator to pick up.","stop_reason":"end_turn","session_id":"05e86322-ba60-40ee-b2cf-41b3eb644ada","total_cost_usd":0.7040674999999998,"usage":{"input_tokens":33,"cache_creation_input_tokens":26068,"cache_read_input_tokens":802905,"output_tokens":5581,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":26068,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":33,"outputTokens":5581,"cacheReadInputTokens":802905,"cacheCreationInputTokens":26068,"webSearchRequests":0,"costUSD":0.7040674999999998,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"3a519687-5a19-47d6-8546-58817140a8bb"}
```
