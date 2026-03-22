<!-- file: tickets/open/0079-audit-cli-command.md -->
# 0079 — Add `scriptorium audit` CLI command

**Area:** audit-agent
**Depends:** 0077

Add an on-demand `scriptorium audit` CLI command.

## Details

In `src/scriptorium.nim`:

1. Add a new `cmdAudit` proc that:
   - Calls `runAudit(getCurrentDir())` from `audit_agent.nim`.
   - Prints the report file path on success.
   - Exits with a non-zero code on failure.

2. Add the command to the case dispatch:
   ```nim
   of "audit":
     cmdAudit()
