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
