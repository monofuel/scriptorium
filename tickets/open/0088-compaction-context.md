**ID:** 0076
**Title:** Sync critical AGENTS.md rules to CLAUDE.md for compaction resilience
**Area:** compaction-context
**Description:**

Claude Code automatically reloads `CLAUDE.md` after context compaction. To ensure critical project rules survive compaction without relying solely on continuation prompts, scriptorium should sync a subset of AGENTS.md rules into a `CLAUDE.md` file.

In `src/scriptorium/init.nim`, add a new proc:

```nim
proc syncClaudeMd*(repoPath: string)
