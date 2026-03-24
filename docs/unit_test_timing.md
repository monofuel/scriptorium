# Unit test timing

Measured with warm Nim compilation cache on host (16 cores, 54GB RAM).

| Test | Time | Notes |
|------|------|-------|
| test_agent_pool.nim | 0.33s | |
| test_agent_runner.nim | 0.35s | |
| test_continuation_builder.nim | 0.33s | |
| test_cycle_detection.nim | 0.33s | |
| test_harness_claude_code.nim | 1.05s | |
| test_harness_codex.nim | 1.23s | |
| test_harness_typoi.nim | 1.20s | |
| test_journal.nim | 0.55s | |
| test_lock_management.nim | 0.33s | |
| **test_logging.nim** | **4.4s** | Slow |
| test_loop_system.nim | 0.34s | |
| test_manager_agent.nim | 0.33s | |
| **test_merge_queue.nim** | **24.0s** | Very slow |
| test_metrics.nim | 0.66s | |
| **test_orchestrator_flow.nim** | **30.0+s** | Very slow (hit 30s timeout) |
| test_orchestrator_planning.nim | 2.46s | |
| test_prior_work.nim | 0.47s | |
| test_prompt_catalog.nim | 0.33s | |
| test_recovery.nim | 1.75s | |
| test_review.nim | 1.46s | |
| test_scriptorium.nim | 0.70s | |
| **test_ticket_assignment.nim** | **3.8s** | Slow |
| test_worktree_health.nim | 0.50s | |

## Summary

- 19 of 23 tests run in under 2.5 seconds.
- `test_merge_queue.nim` and `test_orchestrator_flow.nim` account for nearly all the wall time.
- These two tests block `make test` completion even though everything else finishes quickly.
- In the container with cold compilation cache, total wall time is much worse — coding agents running `make test` get killed before it finishes.
