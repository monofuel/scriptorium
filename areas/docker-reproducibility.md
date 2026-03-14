# Docker Image Reproducibility

V8 feature: pin all external dependencies in the Dockerfile for build reproducibility.

## Scope

**Base image pinning (§33):**
- Base image must be pinned to a specific tag, not `:latest`:
  - `FROM gitea.solution-nine.monofuel.dev/monolab/monolab-nim:2.2.4`
- Optionally pin by digest (`@sha256:...`) for immutable builds; tag pinning is the minimum.

**NPM package version pinning (§33):**
- `@openai/codex` and `@anthropic-ai/claude-code` installed with explicit version specifiers:
  - `RUN npm install --global @openai/codex@<version> @anthropic-ai/claude-code@<version>`
- Pin to current latest stable versions at time of implementation.

**Version traceability (§33):**
- Docker entrypoint or startup log line must print installed versions of pinned dependencies:
  - Base image tag (from build arg or label).
  - `codex --version` output.
  - `claude --version` output.
- Allows operators to confirm which versions are running in a given container.

**Update mechanism (§33):**
- A Makefile target (`make check-updates` or similar) checks for available updates to pinned npm packages and reports whether newer versions exist.
- Advisory only — does not automatically update the Dockerfile.

## V8 Known Limitations

- Docker version pinning requires manual updates when new versions are released.
- `make check-updates` is advisory only.

## Spec References

- Section 33: Docker Image Reproducibility (V8).
