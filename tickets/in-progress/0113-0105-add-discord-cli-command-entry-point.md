# 0105 Add discord CLI command entry point

**Area:** cli-init

## Problem

The spec (Section 1) requires the CLI to support `discord`, but `src/scriptorium.nim` has no case branch for it. The discord area owns the full bot implementation, but the CLI dispatch belongs to cli-init.

## Task

1. In `src/scriptorium.nim`, add a case branch for `"discord"` in the `case args[0]` block.
2. Create a `cmdDiscord` proc that calls a `runDiscord` proc from a new module.
3. Create `src/scriptorium/discord_cli.nim` with a `runDiscord*(repoPath: string)` proc stub that prints an error and quits: `echo "scriptorium: discord command not yet implemented"; quit(1)`.
4. Add `"discord"` to the `Usage` help string (after `audit`).
5. Run `make test` to confirm compilation and existing tests pass.

## Files

- `src/scriptorium.nim`
- `src/scriptorium/discord_cli.nim` (new)

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0113-0105-add-discord-cli-command-entry-point
