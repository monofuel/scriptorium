# 0098 Build architect loop prompt and invoke architect for feedback cycle

**Area:** loop-system

Add the prompt builder and invocation proc that passes loop context to the architect.

## Requirements

1. Add `buildArchitectLoopPrompt*(repoPath: string, planPath: string, goal: string, iterationLog: string, feedbackOutput: string, iterationNumber: int): string` to `src/scriptorium/prompt_builders.nim`.

2. The prompt should contain:
   - The `goal` string.
   - The full `iteration_log.md` contents (the architect's memory across iterations).
   - The feedback output from the latest feedback command.
   - The current iteration number.
   - Instructions telling the architect to:
     - Assess previous results against declared expectations from the prior iteration.
     - Write the next iteration log entry to `iteration_log.md` (iteration number, feedback summary, assessment, strategy, tradeoffs).
     - Update `spec.md`, area files, or create tickets as needed for the next iteration.
     - If results diverge significantly from prior declared expectations, investigate rather than press forward.
     - For hard constraints, treat violations as non-negotiable.

3. Add `runArchitectLoopIteration*(repoPath: string, runner: AgentRunner, feedbackOutput: string): bool` to `src/scriptorium/loop_system.nim`.

   This proc should:
   - Load config to get `loop.goal`.
   - Open a locked plan worktree (`withLockedPlanWorktree` from `lock_management.nim`).
   - Read the existing iteration log with `readIterationLog`.
   - Compute the next iteration number with `nextIterationNumber`.
   - Build the prompt using `buildArchitectLoopPrompt`.
   - Invoke the architect via `runPlanArchitectRequest` (from `architect_agent.nim`), allowing writes to `spec.md`, `areas/`, `tickets/open/`, and `iteration_log.md`.
   - After the architect runs, if it didn't write the iteration log entry (check via `nextIterationNumber` again), append a fallback entry with the feedback output and placeholder assessment/strategy text.
   - Commit the iteration log with `commitIterationLog`.
   - Update the spec hash marker with `writeSpecHashMarker` if spec changed.
   - Return `true` if the architect produced changes.

4. Add a unit test with a mock runner that verifies the prompt contains goal, iteration log content, and feedback output.

## Depends: 0097

## Implementation notes

- Use `runPlanArchitectRequest` from `architect_agent.nim` for the architect invocation.
- Use `withLockedPlanWorktree` from `lock_management.nim` for plan branch access.
- The architect agent config comes from `loadConfig(repoPath).agents.architect`.
- The write allowlist for `enforceWritePrefixAllowlist` should include: `spec.md`, `areas`, `tickets/open`, `iteration_log.md`.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0098-0098-build-architect-loop-prompt-and-invoke-architect-for-feedback-cycle

## Prediction
- predicted_difficulty: hard
- predicted_duration_minutes: 30
- reasoning: Cross-module implementation touching prompt_builders.nim and loop_system.nim with complex orchestration logic (worktree locking, iteration tracking, fallback handling, spec hash updates), plus integration with multiple existing modules (architect_agent, lock_management, config), likely requiring 2+ attempts due to integration risk.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 137\n- Attempt: 5\n- Attempt Count: 5\n- Timeout: no-output\n- Log File: /workspace/.scriptorium/logs/coder/0098/attempt-05.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0098/attempt-05.last_message.txt\n
### Agent Last Message
```text
The code looks complete. Let me verify it compiles and tests pass.
```

### Agent Stdout Tail
```text
"The code looks complete. Let me verify it compiles and tests pass."}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":3497,"cache_creation_input_tokens":6271,"cache_read_input_tokens":18837,"cache_creation":{"ephemeral_5m_input_tokens":6271,"ephemeral_1h_input_tokens":0},"output_tokens":1},"context_management":null},"parent_tool_use_id":null,"session_id":"15b598ba-dc19-43ad-990b-59d9d1421a69","uuid":"a93b940a-ad69-4db3-80e3-49ec9b0aa0ad"}
{"type":"assistant","message":{"model":"claude-opus-4-6","id":"msg_bdrk_01QfqTMpJqi1HHPCthzWskLN","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_bdrk_018pqAcXoEPNZEEFKYyMErem","name":"Bash","input":{"command":"unset CLAUDE_CODE_USE_BEDROCK && make test 2>&1 | tail -40","description":"Run unit tests","timeout":300000}}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":3497,"cache_creation_input_tokens":6271,"cache_read_input_tokens":18837,"cache_creation":{"ephemeral_5m_input_tokens":6271,"ephemeral_1h_input_tokens":0},"output_tokens":1},"context_management":null},"parent_tool_use_id":null,"session_id":"15b598ba-dc19-43ad-990b-59d9d1421a69","uuid":"0503fa34-0cb4-4eda-a7d3-65bcff272c2a"}
```

## Metrics
- wall_time_seconds: 2978
- coding_wall_seconds: 2410
- test_wall_seconds: 0
- attempt_count: 5
- outcome: reopened
- failure_reason: timeout_no_output
- model: claude-opus-4-6
- stdout_bytes: 69754

## Post-Analysis
- actual_difficulty: complex
- prediction_accuracy: underestimated
- brief_summary: Predicted hard, actual was complex with 5 attempt(s) in 49m38s.

## Prediction
- predicted_difficulty: hard
- predicted_duration_minutes: 35
- reasoning: Cross-module implementation touching prompt_builders.nim and loop_system.nim with complex orchestration (worktree locking, iteration tracking, fallback handling, spec hash updates), integrating with 4+ existing modules; previous 5 failed attempts suggest high integration risk, likely 3+ attempts needed.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 137\n- Attempt: 5\n- Attempt Count: 5\n- Timeout: no-output\n- Log File: /workspace/.scriptorium/logs/coder/0098/attempt-05.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0098/attempt-05.last_message.txt\n
### Agent Last Message
```text
All 15 tests pass. Now let me run the full test suite to make sure nothing is broken.
```

### Agent Stdout Tail
```text
pass. Now let me run the full test suite to make sure nothing is broken."}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"cache_creation_input_tokens":904,"cache_read_input_tokens":31167,"cache_creation":{"ephemeral_5m_input_tokens":904,"ephemeral_1h_input_tokens":0},"output_tokens":1},"context_management":null},"parent_tool_use_id":null,"session_id":"f8a780e1-d7d7-4e03-ade8-a89953267895","uuid":"d57c705d-08b6-41bc-88b3-e62368056364"}
{"type":"assistant","message":{"model":"claude-opus-4-6","id":"msg_bdrk_01MrS5N6q7v4jM44dNG53tN7","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_bdrk_01Lf5PcSnkfQgZgsMU5Ro3BX","name":"Bash","input":{"command":"unset CLAUDE_CODE_USE_BEDROCK && make test 2>&1 | tail -50","description":"Run full test suite","timeout":600000}}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"cache_creation_input_tokens":904,"cache_read_input_tokens":31167,"cache_creation":{"ephemeral_5m_input_tokens":904,"ephemeral_1h_input_tokens":0},"output_tokens":1},"context_management":null},"parent_tool_use_id":null,"session_id":"f8a780e1-d7d7-4e03-ade8-a89953267895","uuid":"ed8db506-a0ac-441c-85e3-df9e68ea93da"}
```

## Metrics
- wall_time_seconds: 2857
- coding_wall_seconds: 2852
- test_wall_seconds: 0
- attempt_count: 5
- outcome: reopened
- failure_reason: timeout_no_output
- model: claude-opus-4-6
- stdout_bytes: 87682

## Post-Analysis
- actual_difficulty: complex
- prediction_accuracy: underestimated
- brief_summary: Predicted hard, actual was complex with 5 attempt(s) in 47m37s.

## Prediction
- predicted_difficulty: complex
- predicted_duration_minutes: 55
- reasoning: Cross-module orchestration touching prompt_builders.nim and loop_system.nim with complex integration (worktree locking, iteration tracking, fallback handling, spec hash updates, architect invocation), integrating 4+ modules; two prior rounds of 5 attempts each both timed out during test compilation, indicating persistent integration/compilation issues that will likely require 4+ attempts.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 137\n- Attempt: 5\n- Attempt Count: 5\n- Timeout: no-output\n- Log File: /workspace/.scriptorium/logs/coder/0098/attempt-05.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0098/attempt-05.last_message.txt\n
### Agent Last Message
```text
All 16 tests pass. Let me also verify `make test` works — the previous timeouts were likely from compilation taking too long with a cold cache, which should be warm now.
```

### Agent Stdout Tail
```text
compilation taking too long with a cold cache, which should be warm now."}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"cache_creation_input_tokens":777,"cache_read_input_tokens":30654,"cache_creation":{"ephemeral_5m_input_tokens":777,"ephemeral_1h_input_tokens":0},"output_tokens":2},"context_management":null},"parent_tool_use_id":null,"session_id":"5bf6c07d-f8b3-4595-8aab-2aab73808554","uuid":"0b8c71d9-7c44-4114-85c1-f7e51277a400"}
{"type":"assistant","message":{"model":"claude-opus-4-6","id":"msg_bdrk_014T9auX3sob6WD1BcJPegHU","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_bdrk_013uunxDANPsuH7rzEy3fiwo","name":"Bash","input":{"command":"unset CLAUDE_CODE_USE_BEDROCK && make test 2>&1 | tail -30","description":"Run full test suite","timeout":600000}}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"cache_creation_input_tokens":777,"cache_read_input_tokens":30654,"cache_creation":{"ephemeral_5m_input_tokens":777,"ephemeral_1h_input_tokens":0},"output_tokens":2},"context_management":null},"parent_tool_use_id":null,"session_id":"5bf6c07d-f8b3-4595-8aab-2aab73808554","uuid":"4c94ab33-b4cd-4342-9e9e-d7b578f45d7e"}
```
