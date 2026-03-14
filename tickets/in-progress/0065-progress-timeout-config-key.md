# Add progressTimeout Config Key

**Area:** config-testing

Add the `agents.coding.progressTimeout` config key to `config.nim` as specified in V8, §34.

## Requirements

- Add `codingAgentProgressTimeoutMs*: int` to the `TimeoutConfig` object in `config.nim`.
- Default value: 600_000 (10 minutes in milliseconds, matching the spec default of 10 minutes).
- Load from `scriptorium.json` under a path that maps to `agents.coding.progressTimeout` (integer minutes in JSON, converted to milliseconds internally).
- Merge logic: if the parsed value is > 0, override the default.

## Implementation Notes

- The config key is defined in `config.nim` alongside existing timeout fields (`codingAgentHardTimeoutMs`, `codingAgentNoOutputTimeoutMs`, `codingAgentMaxAttempts`).
- The JSON field name should be `progressTimeout` nested under `agents.coding` or under `timeouts` — follow the existing pattern in `loadConfig`.
- Unit tests in `test_scriptorium.nim` should verify default value and JSON override.

## Acceptance Criteria

- `TimeoutConfig` has `codingAgentProgressTimeoutMs` field with 600_000 default.
- `loadConfig` reads and merges the value from `scriptorium.json`.
- Existing tests continue to pass.
- New unit test verifies default and override behavior.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0065-progress-timeout-config-key
