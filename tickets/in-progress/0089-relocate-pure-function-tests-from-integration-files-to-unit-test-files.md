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
