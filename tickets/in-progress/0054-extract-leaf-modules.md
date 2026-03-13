# Extract Leaf Modules From orchestrator.nim (Batch 1)

**Area:** orchestrator

## Problem

`orchestrator.nim` is 3877 lines and must be decomposed into focused modules per V7 §27. The first extraction batch covers leaf modules with no internal dependencies: `git_ops.nim`, `lock_management.nim`, `ticket_metadata.nim`, and `shared_state.nim`.

## Requirements

### git_ops.nim
- Move all git helper procs: `gitRun`, `gitCheck`, `gitOutput`, `gitMasterHead`, worktree creation/removal, branch operations.
- Export procs used by other modules.

### lock_management.nim
- Move repository locking procs: `acquireLock`, `releaseLock`, `withLockedPlanWorktree`, and related lock file helpers.

### ticket_metadata.nim
- Move ticket parsing and metadata procs: `parseAreaFromTicketContent`, `parseTicketId`, `extractDependencyIds`, `parseMergeQueueItem`, ticket file listing helpers.

### shared_state.nim
- Move shared thread-safe state: `submitPrSummary` buffers, `reviewAction`/`reviewFeedback` buffers, `recordSubmitPr`, `consumeSubmitPr`, `recordReviewDecision`, `consumeReviewDecision`, and the `shouldRun` flag.
- Move type definitions that are shared across modules: `OrchestratorStatus`, `MergeQueueItem`, `SessionStats`, `AgentSlot`, `TicketAssignment`, etc.

### Constraints
- Each module extraction is a single commit that moves procs and updates imports.
- All existing tests (`make test`) must pass after each extraction.
- No behavior changes — pure refactoring.
- Imports follow Nim conventions: std first, then libraries, then local.

## Acceptance Criteria

- `git_ops.nim`, `lock_management.nim`, `ticket_metadata.nim`, `shared_state.nim` exist under `src/scriptorium/`.
- `orchestrator.nim` imports these modules instead of defining the moved procs.
- `make test` passes after each extraction commit.
- No functional changes — identical behavior.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0054-extract-leaf-modules
