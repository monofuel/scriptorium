# 0083-audit-cli-command

**Area:** audit-agent

**Depends:** 0080, 0081

## Description

Add a `scriptorium audit` CLI command that runs the audit agent on demand.

### Requirements

- In `src/scriptorium.nim`, add a new `"audit"` case to the command dispatch.
- Implement `cmdAudit()` that:
  1. Calls `runAuditAgent(getCurrentDir())` to execute the audit.
  2. Calls `writeAuditReport` to save the report.
  3. Prints the report to stdout.
  4. Prints the report file path.
- Update the `Usage` constant to include `scriptorium audit` with description "Run the audit agent on demand".
- The audit command should work standalone — it does not require the orchestrator to be running.
- If the plan branch doesn't exist or spec.md is missing, print a clear error message and exit with code 1.

### Context

Follow the pattern of `cmdPlan` and `cmdAsk` in `src/scriptorium.nim` for CLI command structure. The audit agent reads spec.md from the plan branch via `loadSpecFromPlan` in `architect_agent.nim`.
