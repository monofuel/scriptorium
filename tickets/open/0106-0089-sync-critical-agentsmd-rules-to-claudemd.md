# 0089 — Sync critical AGENTS.md rules to CLAUDE.md

**Area:** compaction-context

**File:** `tickets/open/0089-sync-claude-md.md`

## Problem

Claude Code reloads `CLAUDE.md` after context compaction, making it the most reliable channel for project rules that must survive compaction. Currently, scriptorium syncs `AGENTS.md` (in `src/scriptorium/init.nim`) but does not generate or sync a `CLAUDE.md` file. There is no `CLAUDE.md` in the repository.

## Task

1. In `src/scriptorium/init.nim`, add a `syncClaudeMd` proc that:
   - Reads the existing `AGENTS.md` from the repo path.
   - Writes a `CLAUDE.md` file that references AGENTS.md, e.g.:
