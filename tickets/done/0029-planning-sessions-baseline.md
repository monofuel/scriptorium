# Planning And Ask Sessions Baseline

**Area:** planning-sessions
**Status:** done

## Summary

The `scriptorium plan` and `scriptorium ask` interactive and one-shot workflows are fully implemented and tested.

## What Exists

- Managed plan worktree lifecycle, checked out from `scriptorium/plan` at deterministic `/tmp/scriptorium/.../worktrees/plan` path.
- One-shot planning (`scriptorium plan <prompt>`):
  - Non-blank prompt required.
  - Architect runs with working directory set to managed plan worktree.
  - Repo-root path context included.
  - Post-run write allowlist enforced to `spec.md` only (`enforceWriteAllowlist()`).
  - Commits only when `spec.md` changes, message: `scriptorium: update spec from architect`.
  - Per-repository Architect lock for concurrency safety.
- Interactive planning (`scriptorium plan`):
  - Slash commands: `/show`, `/help`, `/quit`, `/exit`.
  - Unknown slash commands rejected without invoking the Architect.
  - In-memory turn history maintained for multi-turn context.
  - Streamed Architect status output during a turn.
  - At most one commit per turn that changes `spec.md`, message: `scriptorium: plan session turn <n>`.
  - Ctrl+C and EOF exit handling.
- Read-only ask session (`scriptorium ask`):
  - Same managed worktree and repo-root context.
  - Current `spec.md` and conversation history included in prompts.
  - Slash commands: `/show`, `/help`, `/quit`, `/exit`.
  - Streamed output, no file writes, no commits.
- Git repo check skipped inside agent harness for plan worktrees.
- Tests: `test_scriptorium.nim`, `test_prompt_catalog.nim`.
