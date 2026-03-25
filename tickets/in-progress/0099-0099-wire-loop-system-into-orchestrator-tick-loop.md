# 0099 Wire loop system into orchestrator tick loop

**Area:** loop-system

Integrate queue-drain detection and feedback cycle into the orchestrator as tick step 8.

## Requirements

1. In `src/scriptorium/orchestrator.nim`, add the loop system import (`./loop_system`).

2. Add loop iteration state to `runOrchestratorMainLoop`:
   - `var loopIterationCount = 0` — tracks how many feedback cycles have run this session.
   - Load `cfg.loop` at the start alongside `maxAgents`.

3. After step 7 (merge queue processing, around line 330) and before the idle/sleep decision, add step 8:
   - Only if `cfg.loop.enabled` is `true` and `cfg.loop.feedback.len > 0`:
     - Check queue drain: `withPlanWorktree(repoPath, proc(planPath: string): bool = isQueueDrained(planPath))`
     - Also check `runningAgentCount() == 0` (no async agents still running).
     - If drained:
       - If `cfg.loop.maxIterations > 0` and `loopIterationCount >= cfg.loop.maxIterations`:
         - Log `"loop: max iterations reached ({loopIterationCount}/{cfg.loop.maxIterations})"` at INFO level.
         - Do not start another cycle.
       - Otherwise:
         - Increment `loopIterationCount`.
         - Log: `"loop: queue drained, starting feedback cycle (iteration {loopIterationCount})"` at INFO.
         - Call `runFeedbackCommand(repoPath, cfg.loop.feedback)` to get feedback output.
         - Call `runArchitectLoopIteration(repoPath, runner, feedbackOutput)`.
         - Log: `"loop: feedback cycle {loopIterationCount} complete"` at INFO.
         - Set `idle = false` so the orchestrator immediately processes the next tick.

4. Add `loop={loopIterationCount}` to the tick summary log line (the `summary` string near line 339).

5. Add a unit test in `tests/test_orchestrator_flow.nim` (or `tests/test_loop_system.nim`) using a fake runner that verifies:
   - When `loop.enabled = false`, no feedback cycle runs even when queue is drained.
   - When `loop.enabled = true` and queue is drained, the feedback command and architect are invoked.
   - When `maxIterations` is reached, no further cycles run.

## Depends: 0095, 0096, 0098

## Implementation notes

- The orchestrator already uses `withPlanWorktree` extensively — follow the same pattern for drain checks.
- Keep the loop logic minimal in the orchestrator: just detection + invocation. All intelligence lives in the architect prompt and judgment.
- If the feedback command fails, log the error and skip the cycle (don't crash the orchestrator). Use a try/except around the feedback+architect calls, logging the error at WARN level.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0099-0099-wire-loop-system-into-orchestrator-tick-loop

## Prediction
- predicted_difficulty: hard
- predicted_duration_minutes: 30
- reasoning: Cross-module integration wiring loop_system into orchestrator with multiple conditions, worktree interactions, and unit tests requiring fakes — likely 2+ attempts due to integration complexity and test setup.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0099/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0099/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Here's a summary of the changes:

**`src/scriptorium/orchestrator.nim`:**
- Added `loop_system` import
- Added `loopCfg` (loaded from config) and `loopIterationCount` state variable
- Added step 8 after merge queue processing: checks `loopCfg.enabled`, `feedback.len > 0`, queue drained via `isQueueDrained`, and `runningAgentCount() == 0`. Respects `maxIterations` limit. Calls `runFeedbackCommand` + `runArchitectLoopIteration` with try/except for error resilience. Sets `idle = false` on success.
- Added `loop={loopIterationCount}` to the tick summary log line

**`tests/test_loop_system.nim`:**
- Added 3 orchestrator loop unit tests with fake runners:
  - `testLoopDisabledNoCycle` — loop disabled, no feedback cycle even when drained
  - `testLoopEnabledDrainedQueueTriggersCycle` — loop enabled + drained → feedback + architect invoked
  - `testLoopMaxIterationsReached` — only one cycle runs with `maxIterations=1`
```

### Agent Stdout Tail
```text
mmary log line\n\n**`tests/test_loop_system.nim`:**\n- Added 3 orchestrator loop unit tests with fake runners:\n  - `testLoopDisabledNoCycle` — loop disabled, no feedback cycle even when drained\n  - `testLoopEnabledDrainedQueueTriggersCycle` — loop enabled + drained → feedback + architect invoked\n  - `testLoopMaxIterationsReached` — only one cycle runs with `maxIterations=1`","stop_reason":"end_turn","session_id":"b2d0054b-1dd8-4a06-a6fe-9c06297c0343","total_cost_usd":2.7802617500000006,"usage":{"input_tokens":55,"cache_creation_input_tokens":156125,"cache_read_input_tokens":2906461,"output_tokens":14039,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":156125},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":55,"outputTokens":14039,"cacheReadInputTokens":2906461,"cacheCreationInputTokens":156125,"webSearchRequests":0,"costUSD":2.7802617500000006,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"150875c9-f859-4b39-86eb-ecb98809b39a"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 38s

**Review Reasoning:** Let me read the relevant source files to understand the context.
I've reviewed the diff thoroughly. Here's my assessment:

**Spec compliance:** All requirements met correctly. Queue-drain detection checks open + in-progress + pending merge. `maxIterations` 0 means infinite, non-zero enforces limit. Feedback command runs synchronously, architect invoked with output. Error handling via try/except with logWarn matches the implementation notes. `idle = false` set on success. `loop={loopIterationCount}` in tick summary.

**Convention compliance:** Import style follows single-block bracket syntax with correct ordering. Variables use camelCase. Constants use PascalCase. Doc comments on new procs. Format strings use `&` with variables extracted before interpolation.

**Code quality:** No dead code, no unused imports, no leftover artifacts. The three unit tests cover all required scenarios (disabled, enabled+drained, maxIterations). Test structure uses proper fakes in a unit test file as required.

No issues found.
Approved. The implementation cleanly wires the loop system into the orchestrator tick loop with correct queue-drain detection, maxIterations enforcement, error resilience, and all three required unit tests.

## Merge Queue Failure
- Summary: Wire loop system into orchestrator tick loop as step 8. Added loop_system import, loopIterationCount state, queue-drain detection with feedback cycle invocation after step 7, maxIterations limit enforcement, loop count in tick summary log, and three unit tests verifying disabled/enabled/max-iterations behavior.\n- Failed gate: git merge master (rebase retry also failed)\n
### Merge Output
```text
Rebasing (2/3)
Rebasing (3/3)
Successfully rebased and updated refs/heads/scriptorium/ticket-0099.
```

### Quality Check Output
```text
Auto-merging tests/test_loop_system.nim
CONFLICT (content): Merge conflict in tests/test_loop_system.nim
Automatic merge failed; fix conflicts and then commit the result.
```

## Metrics
- wall_time_seconds: 1027
- coding_wall_seconds: 362
- test_wall_seconds: 0
- attempt_count: 1
- outcome: reopened
- failure_reason: test_failure
- model: claude-opus-4-6
- stdout_bytes: 557143

## Post-Analysis
- actual_difficulty: hard
- prediction_accuracy: accurate
- brief_summary: Predicted hard, actual was hard with 1 attempt(s) in 17m7s.

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Reopened due to merge conflict in test file only — the implementation code was approved and correct; resolving the conflict and ensuring tests pass is a focused single-file fix with no logic changes needed.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0099/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0099/attempt-01.last_message.txt\n
### Agent Last Message
```text
PR submitted. Here's a summary of the changes:

**`src/scriptorium/orchestrator.nim`:**
- Added `loop_system` to imports
- Added `loopCfg` and `loopIterationCount` state variables in `runOrchestratorMainLoop`
- Added step 8 after merge queue processing: checks `loopCfg.enabled`, `feedback.len > 0`, queue drained via `isQueueDrained`, and `runningAgentCount() == 0`. Respects `maxIterations` limit. Calls `runFeedbackCommand` + `runArchitectLoopIteration` with try/except for error resilience. Sets `idle = false` on success.
- Added `loop={loopIterationCount}` to the tick summary log line

**`tests/test_loop_system.nim`:**
- Added 3 unit tests with fake runners:
  - `testLoopDisabledNoCycle` — loop disabled, no feedback cycle even when drained
  - `testLoopEnabledDrainedQueueTriggersCycle` — loop enabled + drained → feedback + architect invoked
  - `testLoopMaxIterationsReached` — only one cycle runs with `maxIterations=1`
```

### Agent Stdout Tail
```text
loop={loopIterationCount}` to the tick summary log line\n\n**`tests/test_loop_system.nim`:**\n- Added 3 unit tests with fake runners:\n  - `testLoopDisabledNoCycle` — loop disabled, no feedback cycle even when drained\n  - `testLoopEnabledDrainedQueueTriggersCycle` — loop enabled + drained → feedback + architect invoked\n  - `testLoopMaxIterationsReached` — only one cycle runs with `maxIterations=1`","stop_reason":"end_turn","session_id":"b41fb145-50bc-47ff-859b-586dca0f5752","total_cost_usd":1.042044,"usage":{"input_tokens":2019,"cache_creation_input_tokens":55952,"cache_read_input_tokens":988098,"output_tokens":7528,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":55952},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":2019,"outputTokens":7528,"cacheReadInputTokens":988098,"cacheCreationInputTokens":55952,"webSearchRequests":0,"costUSD":1.042044,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"c52d460b-6771-4a39-bdf3-4b74efe308fd"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 53s

**Review Reasoning:** Now let me verify the `submit_review` tool is available.


I've reviewed the diff thoroughly. Here's my assessment:

**Spec compliance:** All §22 and §3 requirements are correctly implemented. Queue-drain checks all three conditions (no open, no in-progress, no pending merge). `maxIterations` 0 means infinite, non-zero enforces the limit. Feedback command runs synchronously, architect is invoked with goal + iteration log + feedback output. Error handling via try/except with `logWarn` matches the implementation notes requirement. `idle = false` set on successful cycle. `loop={loopIterationCount}` added to tick summary.

**Convention compliance:** Import style correct (single block, bracket syntax, std/ then local). Constants use PascalCase (`LoopWriteAllowPrefixes`, `LoopScopeName`, `LoopTicketId`). Variables use camelCase. Doc comments on all new procs. Format strings use `&` with variables extracted before interpolation. Grouped `const`/`let`/`var` blocks.

**Code quality:** No dead code, no unused imports, no leftover artifacts. The `runArchitectLoopIteration` proc properly uses `withLockedPlanWorktree` for the commit lock (matching the spec's transactional commit lock pattern). The try/except in the orchestrator is justified by the ticket's explicit requirement for error resilience.

**Tests:** All three required scenarios covered — disabled skips cycle, enabled+drained triggers cycle, maxIterations enforced. Tests use fake runners as required for unit tests.

No issues found.


Review approved. The implementation cleanly wires the loop system into the orchestrator tick loop with correct queue-drain detection, maxIterations enforcement, error resilience, and all three required unit tests. No convention, spec, or code quality issues found.

## Merge Queue Failure
- Summary: Wire loop system into orchestrator tick loop as step 8. Added loop_system import, loopIterationCount state, queue-drain detection with feedback cycle invocation after step 7, maxIterations limit enforcement, error resilience via try/except with WARN logging, loop count in tick summary log, and three unit tests verifying disabled/enabled/max-iterations behavior.\n- Failed gate: git merge master (rebase retry also failed)\n
### Merge Output
```text
Current branch scriptorium/ticket-0099 is up to date.
```

### Quality Check Output
```text
Auto-merging tests/test_loop_system.nim
CONFLICT (content): Merge conflict in tests/test_loop_system.nim
Automatic merge failed; fix conflicts and then commit the result.
```

## Metrics
- wall_time_seconds: 735
- coding_wall_seconds: 179
- test_wall_seconds: 0
- attempt_count: 1
- outcome: reopened
- failure_reason: test_failure
- model: claude-opus-4-6
- stdout_bytes: 370450

## Post-Analysis
- actual_difficulty: hard
- prediction_accuracy: accurate
- brief_summary: Predicted hard, actual was hard with 1 attempt(s) in 12m15s.

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 15
- reasoning: Reopened solely for a merge conflict in test_loop_system.nim — implementation was approved twice; just needs conflict resolution against master and recommit, no logic changes required.
