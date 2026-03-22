<!-- file: tickets/open/0078-audit-drain-trigger.md -->
# 0078 — Trigger audit agent when merge queue drains

**Area:** audit-agent
**Depends:** 0077

Wire the audit agent into the orchestrator so it runs when the merge queue drains.

## Details

In `src/scriptorium/orchestrator.nim`:

1. Add state tracking for merge queue drain detection:
   - Track a `mergeQueueWasActive: bool` flag that is set to `true` whenever `processMergeQueue` returns `true` (processed an item).
   - When the orchestrator goes idle (`idle = true`) and `mergeQueueWasActive` is true, the queue has drained.

2. After the idle detection block (around line 301-308), add audit trigger logic:
   - If queue drained AND `needsAudit(repoPath)` returns true:
     - Start the audit agent using `startAgentAsync` from `agent_pool.nim` (it shares the pool slot like managers/coders).
     - Reset `mergeQueueWasActive` to false.
   - The audit agent should run as a background agent using a shared pool slot.

3. Add secondary trigger: detect spec changes. After the architect runs and commits changes, check if `spec.md` was modified. If so, set a flag to trigger audit on next idle.

4. Import `audit_agent` module in orchestrator.

## Verification

- `make test` passes.
- Audit triggers only after merge queue drains (not on every idle tick).
- Audit does not block the merge queue or other agents beyond consuming one pool slot.
