# Planning And Ask Sessions

Covers the `scriptorium plan` and `scriptorium ask` interactive and one-shot workflows.

## Scope

- Managed plan worktree lifecycle, checked out from `scriptorium/plan` at a deterministic `/tmp/scriptorium/.../worktrees/plan` path.
- One-shot planning (`scriptorium plan <prompt>`):
  - Non-blank prompt required.
  - Architect runs with working directory set to managed plan worktree.
  - Repo-root path context included.
  - Post-run write allowlist enforced to `spec.md` only.
  - Commit only when `spec.md` changes, message: `scriptorium: update spec from architect`.
  - Per-repository Architect lock for concurrency safety.
- Interactive planning (`scriptorium plan`):
  - Session slash commands: `/show`, `/help`, `/quit`, `/exit`.
  - Unknown slash commands rejected without invoking the Architect.
  - In-memory turn history, streamed Architect status output.
  - At most one commit per turn that changes `spec.md`, message: `scriptorium: plan session turn <n>`.
  - Ctrl+C and EOF exit handling.
- Read-only ask session (`scriptorium ask`):
  - Same managed worktree and repo-root context.
  - Current `spec.md` and conversation history in prompts.
  - Session slash commands: `/show`, `/help`, `/quit`, `/exit`.
  - Streamed output, no file writes, no commits.
- Git repo check skipped inside agent harness for plan worktrees.

## Spec References

- Section 2: Planning And Ask Sessions.
