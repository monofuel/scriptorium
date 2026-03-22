# 0082-audit-agent-orchestrator-trigger

**Area:** audit-agent

**Depends:** 0079, 0081

## Description

Wire the audit agent into the orchestrator main loop so it triggers when the merge queue drains.

### Requirements

- In `src/scriptorium/orchestrator.nim`, after the merge queue processing step (Step 7), add logic to detect when the merge queue has drained:
  - Track whether the merge queue was non-empty on the previous tick (add a `var mergeQueueWasActive: bool` to the loop state).
  - When the queue transitions from active to empty (was active, now `queueItems.len == 0` and no active item), and `auditShouldRun` returns true, spawn the audit agent.
- The audit agent runs as a background task using the shared agent pool. It should use `startCodingAgentAsync` patterns or a new `startAuditAgentAsync` proc that occupies one pool slot.
- Alternatively, for simplicity in the initial implementation, run the audit agent synchronously within the tick (like the architect) since it uses a cheap model and should be fast. Log the wall time.
- After the audit completes, call `writeAuditReport` and log the result path.
- Add the audit step to the tick summary log line (e.g., `audit=ran` or `audit=skipped`).
- Also trigger an audit when the spec changes (detected via `architectChanged` being true in the tick).

### Context

The merge queue is processed in `processMergeQueue` which returns a bool. Track queue state across ticks to detect the "drain" transition. The `listMergeQueueItems` proc in `merge_queue.nim` returns pending items — when this goes from non-empty to empty, the queue has drained.
