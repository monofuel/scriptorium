# 0093 Set concurrency.maxAgents default to 1

**Area:** config-testing
**Priority:** low

## Context

The spec (V5, Section 24) defines `concurrency.maxAgents` with a default of 1. The current `defaultConfig()` in `src/scriptorium/config.nim` sets `maxAgents: 4`. This should be corrected to match the spec default.

## Task

1. In `src/scriptorium/config.nim`, change the `maxAgents` default in `defaultConfig()` from `4` to `1`.
2. Update `tests/test_config.nim`:
   - In `testDefaultConfigValues`, change the assertion from `cfg.concurrency.maxAgents == 4` to `cfg.concurrency.maxAgents == 1`.
   - In `testPartialJsonMerge`, change the assertion from `cfg.concurrency.maxAgents == 4` to `cfg.concurrency.maxAgents == 1`.
   - In `testDashboardConfigLoading`, change the assertion from `cfg.concurrency.maxAgents == 4` to `cfg.concurrency.maxAgents == 1`.
3. Check for any other test files that assert `maxAgents == 4` and update them.
4. Run `make test` and confirm all tests pass.

## Acceptance criteria

- `defaultConfig().concurrency.maxAgents == 1`.
- All unit tests updated and passing.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0093-0093-set-concurrencymaxagents-default-to-1

## Prediction
- predicted_difficulty: trivial
- predicted_duration_minutes: 5
- reasoning: Single constant change from 4 to 1 in config plus updating three test assertions to match — purely mechanical find-and-replace with no logic changes.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0093/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0093/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Changed `maxAgents` default from 4 to 1 in `src/scriptorium/config.nim` and updated 4 test assertions across `tests/test_config.nim` and `tests/integration_scriptorium.nim`. All tests pass.
```

### Agent Stdout Tail
```text
use_id":null,"session_id":"31ff9353-7679-4c23-b567-64c759096e72","uuid":"cac3c98a-5727-42d7-b3c6-72089a90afbb"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":63420,"duration_api_ms":56346,"num_turns":18,"result":"Done. Changed `maxAgents` default from 4 to 1 in `src/scriptorium/config.nim` and updated 4 test assertions across `tests/test_config.nim` and `tests/integration_scriptorium.nim`. All tests pass.","stop_reason":"end_turn","session_id":"31ff9353-7679-4c23-b567-64c759096e72","total_cost_usd":0.382854,"usage":{"input_tokens":14,"cache_creation_input_tokens":26726,"cache_read_input_tokens":287993,"output_tokens":2870,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":26726,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":14,"outputTokens":2870,"cacheReadInputTokens":287993,"cacheCreationInputTokens":26726,"webSearchRequests":0,"costUSD":0.382854,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"665ebd72-51e5-4cd1-8b5b-3bfbc9121b9e"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 16s

**Review Reasoning:** The diff is straightforward and correct:

1. **Config change**: `maxAgents: 4` → `maxAgents: 1` in `defaultConfig()` — matches spec V5 Section 24.
2. **Test updates**: All 4 assertions updated (`test_config.nim` × 3, `integration_scriptorium.nim` × 1).
3. **No convention violations**, no dead code, no unrelated changes.
4. **Agent confirmed tests pass**.

Clean mechanical change that matches the ticket exactly.
Review approved. The change correctly aligns `concurrency.maxAgents` default with the spec.

## Merge Queue Success
- Summary: Changed concurrency.maxAgents default from 4 to 1 in defaultConfig() to match spec V5 Section 24. Updated all related assertions in test_config.nim (3 occurrences) and integration_scriptorium.nim (1 occurrence).\n
### Quality Check Output
```text
iting to /dev/shm/cc42z8j6.s: No space left on device
[tests/integration_orchestrator_flow.nim]  1555 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
[tests/integration_orchestrator_flow.nim] /home/scriptorium/.cache/nim/integration_orchestrator_flow_d/@ptimes.nim.c:3801:1: fatal error: error writing to /dev/shm/cc4yvM2e.s: No space left on device
[tests/integration_orchestrator_flow.nim]  3801 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
[tests/integration_orchestrator_flow.nim] /home/scriptorium/.cache/nim/integration_orchestrator_flow_d/@ptables.nim.c:8698:1: fatal error: error writing to /dev/shm/ccVwJhDG.s: No space left on device
[tests/integration_orchestrator_flow.nim]  8698 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
[tests/integration_orchestrator_flow.nim] /home/scriptorium/.cache/nim/integration_orchestrator_flow_d/@psystem.nim.c:14454:1: fatal error: error writing to /dev/shm/ccRcbiqC.s: No space left on device
[tests/integration_orchestrator_flow.nim] 14454 | }
[tests/integration_orchestrator_flow.nim]       | ^
[tests/integration_orchestrator_flow.nim] compilation terminated.
arness_d/@ptimes.nim.c:3812:1: fatal error: error writing to /dev/shm/ccgyTYTQ.s: No space left on device
[tests/integration_claude_code_harness.nim]  3812 | }
[tests/integration_claude_code_harness.nim]       | ^
[tests/integration_claude_code_harness.nim] compilation terminated.
[tests/integration_claude_code_harness.nim] /home/scriptorium/.cache/nim/integration_claude_code_harness_d/@psystem.nim.c:11927:1: fatal error: error writing to /dev/shm/ccy1sfx3.s: No space left on device
[tests/integration_claude_code_harness.nim] 11927 | }
[tests/integration_claude_code_harness.nim]       | ^
[tests/integration_claude_code_harness.nim] compilation terminated.
```

## Metrics
- wall_time_seconds: 324
- coding_wall_seconds: 64
- test_wall_seconds: 16
- attempt_count: 1
- outcome: done
- failure_reason: 
- model: claude-opus-4-6
- stdout_bytes: 214810

## Post-Analysis
- actual_difficulty: easy
- prediction_accuracy: underestimated
- brief_summary: Predicted trivial, actual was easy with 1 attempt(s) in 5m24s.
