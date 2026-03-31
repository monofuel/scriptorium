# Relocate pure-function tests from integration files to unit test files

**Area:** agent-execution

Per AGENTS.md conventions: "If it uses a mock, fake, or stub for a core dependency, it is a unit test. Put it in `tests/test_*.nim`." and "Do not put mocked tests in integration test files. Do not call real services in unit test files."

Several test suites in integration test files are pure-function tests that do not call real external services. They should be in `tests/test_*.nim` files:

1. **`tests/integration_logging.nim`** — the `formatDuration` suite (lines ~352–366) tests a pure function from `output_formatting.nim`. Move to `tests/test_output_formatting.nim` (create if it doesn't exist from ticket 0074, or add to it).

2. **`tests/integration_metrics.nim`** — the following suites test pure functions or in-memory state with no external service calls:
   - `parseMetricField` suite (lines 9–29)
   - `per-ticket metrics` suite (lines 31–127): `formatMetricsNote`, `appendMetricsNote`, `cleanupTicketTimings`
   - `ticket difficulty prediction` suite (lines 129–312): `parsePredictionResponse`, `formatPredictionNote`, `appendPredictionNote`, `buildPredictionPrompt`, `parsePredictionFromContent`, `classifyActualDifficulty`, `compareDifficulty`, `formatPostAnalysisNote`, `appendPostAnalysisNote`, `runPostAnalysis`
   - `health cache persistence` suite (lines 314–393): `readHealthCache`, `writeHealthCache`
   - `per-ticket submit_pr state` suite (lines 395–450): `consumeSubmitPrSummary`, `recordSubmitPrSummary`, `setActiveTicketWorktree`, `clearActiveTicketWorktree`, `getActiveTicketWorktree`
   - `agent slot types` suite (lines 452–476)
   - `token budget tracking` suite (lines 484–523)

   Exception: `runTicketPrediction` tests (lines 261–312) use a fake runner with plan branch operations — these are proper integration tests and should stay.

For each relocated suite:
- Move the test code to the appropriate `tests/test_*.nim` file.
- Remove the moved suite from the integration file.
- Ensure imports are correct in the new location.
- Verify both `make test` and `make integration-test` still pass after the move.

Target files:
- `tests/test_output_formatting.nim` — formatDuration, formatMetricsNote, appendMetricsNote, formatPredictionNote, formatPostAnalysisNote, appendPostAnalysisNote, parseMetricField
- `tests/test_ticket_analysis.nim` (new) — parsePredictionResponse, parsePredictionFromContent, classifyActualDifficulty, compareDifficulty, runPostAnalysis, buildPredictionPrompt
- `tests/test_shared_state.nim` (new) — cleanupTicketTimings, submit_pr state, active ticket worktree, token budget tracking, health cache persistence

**Depends:** 0074

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0089-relocate-pure-function-tests-from-integration-files-to-unit-test-files

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Mechanical test relocation across multiple files with no logic changes, but touches many suites and requires creating new files with correct imports — moderate volume, low complexity, one attempt expected.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /workspace/.scriptorium/logs/coder/0089/attempt-01.jsonl\n- Last Message File: /workspace/.scriptorium/logs/coder/0089/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. All pure-function test suites have been relocated from integration files to proper unit test files:

- **`tests/test_output_formatting.nim`** — added `formatDuration`, `parseMetricField`, per-ticket metrics formatting, prediction/post-analysis formatting suites
- **`tests/test_ticket_analysis.nim`** (new) — prediction parsing, difficulty classification, comparison, post-analysis, and prompt building
- **`tests/test_shared_state.nim`** (new) — ticket timing cleanup, health cache persistence, submit_pr state, agent slot types, token budget tracking

Only `runTicketPrediction` tests remain in `integration_metrics.nim` as they use plan branch operations.
```

### Agent Stdout Tail
```text
**`tests/test_ticket_analysis.nim`** (new) — prediction parsing, difficulty classification, comparison, post-analysis, and prompt building\n- **`tests/test_shared_state.nim`** (new) — ticket timing cleanup, health cache persistence, submit_pr state, agent slot types, token budget tracking\n\nOnly `runTicketPrediction` tests remain in `integration_metrics.nim` as they use plan branch operations.","stop_reason":"end_turn","session_id":"f27f8129-c94d-41ee-ab1b-49ccbb1462a7","total_cost_usd":2.2226995,"usage":{"input_tokens":8730,"cache_creation_input_tokens":131602,"cache_read_input_tokens":1932924,"output_tokens":15603,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":131602},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":8730,"outputTokens":15603,"cacheReadInputTokens":1932924,"cacheCreationInputTokens":131602,"webSearchRequests":0,"costUSD":2.2226995,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"531207e6-1ed1-4f31-bd6c-ea03ee70d023"}
```

## Review
**Review:** approved
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 1m13s

**Review Reasoning:** The diff is a clean mechanical relocation of pure-function tests. Let me verify the key points:

- **All suites moved to correct target files** per ticket spec: `formatDuration`/`parseMetricField`/metrics formatting → `test_output_formatting.nim`, prediction parsing/difficulty functions → `test_ticket_analysis.nim`, shared state/health cache/budget tracking → `test_shared_state.nim`.
- **`runTicketPrediction` correctly remains** in `integration_metrics.nim` as it uses plan branch operations.
- **Imports follow conventions**: single block, bracket syntax, std/ first then local. All imports appear used.
- **Integration file cleanup is correct**: removed imports in `integration_metrics.nim` match what was removed, remaining imports support the kept `runTicketPrediction` test.
- **No behavioral changes**: test code is moved verbatim (with one minor improvement: `createTempDir` instead of `getTempDir() / literal` in health cache tests, which is safer against collisions).
- **Module comments updated** appropriately in both integration files.

One minor note: `formatPredictionNote`, `appendPredictionNote`, `formatPostAnalysisNote`, and `appendPostAnalysisNote` tests were moved from the original "ticket difficulty prediction" suite into the "per-ticket metrics" suite in `test_output_formatting.nim`. This is a slight suite reorganization but doesn't affect correctness and the target file matches the ticket spec.
Review approved. Clean mechanical relocation with correct target files, proper import updates, and no behavioral changes.
