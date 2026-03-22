# v14 post-analysis

## Spec rewrite size limit

**Problem**: The `scriptorium plan` one-shot command failed to rewrite
`spec.md` (776 lines, ~48KB). The architect agent read the file, said "Now
I'll rewrite this as a flat topic-based blueprint", then ran out of output
tokens before actually performing the Write operation.

**Root cause**: Claude Code's `--print` mode has a max output tokens limit.
A full rewrite of a large spec requires reading the entire file (~48KB) into
context, then producing a similarly-sized output. The agent used most of its
output budget on thinking/planning and couldn't complete the write.

**Implications**: This is a structural limit on spec size. If the spec grows
beyond what an agent can rewrite in a single turn, the architect can no longer
restructure it. This affects:

- One-shot `scriptorium plan "<prompt>"` commands that request major rewrites
- Orchestrator-driven spec updates via `runPlanArchitectRequest`
- Any future "spec consolidation" automation

**Workarounds for now**:

1. **Interactive `scriptorium plan`**: Multi-turn sessions can break the
   rewrite into chunks — "rewrite sections 1-10", then "rewrite sections
   11-20", etc. Each turn stays within output limits.
2. **Manual edit via git worktree**: Edit `spec.md` directly on the plan
   branch using a worktree checkout. No agent needed.
3. **Multiple one-shot calls**: Break the rewrite into smaller operations —
   "remove all Known Limitations sections", then "merge V2 and V3 into
   topic headings", etc. Flaky but possible.

**Future considerations**:

- Should scriptorium enforce a spec size limit or warn when spec.md is
  getting too large?
- Could the architect be given a "chunked rewrite" mode where it rewrites
  one section at a time across multiple agent invocations?
- Should large specs be split into multiple files (e.g. `spec/cli.md`,
  `spec/orchestrator.md`) that the architect manages independently?
- The continuation/retry mechanism could help here — if the agent runs out
  of output mid-write, a retry could pick up where it left off. But the
  current retry logic is designed for coding agents, not planning.
