# Merge Queue Area — V5 Complete

**Area:** merge-queue
**Status:** done

## Summary

All merge-queue scope items through V5 are fully implemented and tested:

- **Single-flight processing**: At most one pending item consumed per `processMergeQueue` call.
- **Queue processing flow**: `active.md` tracking, merge master into branch, `make test` + `make integration-test` quality gates, fast-forward merge on success, ticket state transitions (in-progress → done on success, in-progress → open on failure, in-progress → stuck after max failures).
- **Queue metadata cleanup**: `active.md` cleared on every terminal path. Stale items (ticket already moved) detected and removed.
- **Merge success/failure notes**: Include submit summary and truncated output tails.
- **Pre-submit test gate (V4 §20)**: `submit_pr` MCP handler runs `make test` before enqueuing. Failure returns error to agent. Pass enqueues normally.
- **Review agent integration (V4 §21)**: Every pending item goes through `runReviewAgent` before quality gates. Approved → proceed. Changes requested → reopen ticket.
- **FIFO ordering (V5 §25)**: Monotonic queue item IDs, filename-sorted listing ensures submission order. Single-flight processor handles one item per tick.
- **Legacy worktree cleanup**: `.scriptorium/worktrees/` paths removed on assignment and cleanup passes.

## Prior Tickets

- 0026: Merge queue baseline
- 0040: Pre-submit test gate
