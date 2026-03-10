# Stall Detection And Automatic Continuation

V2 feature: detect coding agent stalls (exit without `submit_pr`) and retry with test-aware continuation prompts.

## Scope

- Stall definition: coding agent turn completes (process exits) without calling the `submit_pr` MCP tool.
- On stall, orchestrator automatically retries with a continuation prompt containing:
  - Full original ticket content.
  - Reminder to continue working and call `submit_pr` when done.
- Retries use existing bounded retry mechanism (`maxAttempts` in `AgentRunRequest`).
- Continuation prompt is distinct from initial prompt — indicates this is a retry after a stall.
- Each stall retry logged with attempt number and ticket ID.
- Test-aware stall detection (augments, does not replace basic stall detection):
  - Before sending continuation prompt, run `make test` in the agent's worktree.
  - Capture exit code and output.
  - If tests fail: include test failure output (truncated if long) and directive to fix failing tests.
  - If tests pass: include note that tests pass and directive to continue and submit.

## V2 Known Limitations

- Stall detection is per-turn only — does not detect in-turn lack of progress.
- Test-aware detection runs `make test` only, not `make integration-test`.
- Coding agent promotions and manager-driven retries are out of scope.

## Spec References

- Section 11: Stall Detection And Automatic Continuation (V2).
- Section 12: Test-Aware Stall Detection (V2).
