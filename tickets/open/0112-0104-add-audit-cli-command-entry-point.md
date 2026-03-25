# 0104 Add audit CLI command entry point

**Area:** cli-init

## Problem

The spec (Section 1) requires the CLI to support `audit`, but `src/scriptorium.nim` has no case branch for it. The audit agent area owns the full implementation, but the CLI dispatch belongs to cli-init.

## Task

1. In `src/scriptorium.nim`, add a case branch for `"audit"` in the `case args[0]` block.
2. Create a `cmdAudit` proc that calls a `runAudit` proc from a new or existing module.
3. Create `src/scriptorium/audit_agent_cli.nim` with a `runAudit*(repoPath: string)` proc stub that prints an error and quits: `echo "scriptorium: audit command not yet implemented"; quit(1)`.
4. Add `"audit"` to the `Usage` help string (after `ask`).
5. Run `make test` to confirm compilation and existing tests pass.

## Files

- `src/scriptorium.nim`
- `src/scriptorium/audit_agent_cli.nim` (new)
