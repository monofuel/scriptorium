# Extract Mid-Level Modules From orchestrator.nim (Batch 2)

**Area:** orchestrator
**Depends:** 0054

## Problem

Continuing the V7 §27 module split after leaf modules are extracted. This batch covers mid-level modules: `prompt_builders.nim`, `output_formatting.nim`, `ticket_analysis.nim`, and `health_checks.nim`.

## Requirements

### prompt_builders.nim
- Move all prompt building procs: `buildCodingAgentPrompt`, `buildArchitectAreasPrompt`, `buildManagerTicketPrompt`, `buildReviewAgentPrompt`, `buildInteractivePlanPrompt`, `buildAskPrompt`, `buildPlanScopePrompt`, `buildContinuationPrompt`.
- Move related helpers like `truncateTail` and prompt template rendering.

### output_formatting.nim
- Move output formatting procs: `formatMetricsSection`, `formatPostAnalysisSection`, agent run notes formatting, merge queue output preview formatting.

### ticket_analysis.nim
- Move ticket analysis procs: `dependenciesSatisfied`, difficulty prediction parsing, post-analysis logic.

### health_checks.nim
- Move master health check procs: `checkMasterHealth`, health cache reading/writing (`readHealthCache`, `writeHealthCache`), `MasterHealthState` type and related logic.

### Constraints
- Each module extraction is a single commit.
- All existing tests must pass after each commit.
- No behavior changes.

## Acceptance Criteria

- `prompt_builders.nim`, `output_formatting.nim`, `ticket_analysis.nim`, `health_checks.nim` exist under `src/scriptorium/`.
- `orchestrator.nim` imports these modules.
- `make test` passes after each extraction commit.
- No functional changes.
