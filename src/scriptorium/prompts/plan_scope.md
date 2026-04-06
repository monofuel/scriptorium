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
- Historical records belong in `docs/`, not spec.md.
  This includes: "changes already applied" lists, confirmed dead ends,
  completed/retired ticket post-mortems, diagnostic tables from specific runs,
  and inline code blocks longer than ~10 lines (move to area files or tickets).
- When updating spec.md after an iteration, update the *current state* sections
  in place. Do not append new sections for each iteration's results.

## Docs organization rules

The `docs/` directory on the plan branch holds architect reference material:
iteration records, findings, analysis, and other durable context.

- No single file over 200 lines. Split by subtopic or time period.
- Use folders to group by topic (e.g. `docs/iterations/`, `docs/findings/`).
- Files should be self-contained — include enough context to be useful in isolation.
- Prefer updating or deleting over appending. Superseded findings should be
  updated or removed, not contradicted by a newer file.
- `docs/iterations/` contains per-iteration records (one file per iteration).
  These are append-only journal entries. Other docs are living reference material.
