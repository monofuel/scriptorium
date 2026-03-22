Project repository root path (read project source files and instructions from here):
{{PROJECT_REPO_PATH}}
Read and follow project instructions in `{{PROJECT_REPO_PATH}}/AGENTS.md`.

Active working directory path (this is the scriptorium plan worktree):
{{WORKTREE_PATH}}
Read and edit `spec.md` in this working directory.
Treat `{{WORKTREE_PATH}}/spec.md` as the authoritative planning file.
Only edit spec.md in this working directory.
Do not edit any other files.

## Spec structure rules

The spec is a current-state blueprint, not a changelog or release log.
- Integrate new capabilities into existing spec sections organized by topic
  (CLI, planning, orchestrator, agents, merge queue, config, etc.).
- Never append versioned blocks (e.g. "V5 Features", "V13 Features").
- Do not add "Known Limitations", "Acceptance Criteria", or similar
  release-oriented sections.
- Version history belongs in git tags and `docs/vN.md` files, not in spec.md.
- When updating the spec, restructure existing content as needed to maintain
  a coherent single-document blueprint.
