# Review approval gating

Version 20.0.3 requires both successful reviewer completion and an explicit
`approve` or `approve_with_warnings` submission through the current ticket's
scoped MCP session before running quality gates or advancing the default branch.
`request_changes` retains its feedback and reopens the ticket. The first valid
submission wins; a subsequent approval cannot overwrite a rejection.

Missing submissions already became `request_changes` in the v20 ACP migration.
The historical 19a5c2c checkout still defaulted to approval when a review stalled.
The remaining v20 defect accepted an approval even when its reviewer subsequently
failed, timed out, or was cancelled. Version 20.0.3 rejects those outcomes as well
as typed failures and incomplete ACP stop reasons. Malformed MCP payloads do not
record a verdict. Expired or other-session submissions cannot approve the current
review. An exception still propagates, with its scoped endpoint unregistered and
the queue item retained for recovery; it cannot advance the default branch.

`tests/test_review_gating.nim` exercises the real merge-queue code and temporary
Git repositories with injected reviewers, without contacting providers. It
asserts that rejected outcomes never run the quality targets, change the default
branch hash, merge the ticket's file, or complete the ticket. Successful explicit
approvals exercise both quality targets and merge. `tests/test_mcp_server.nim`
also checks malformed payloads and session completion state. These are unit tests
with controlled reviewer dependencies, not live-provider integration coverage.

Release validation passed all 51 offline unit-test files and
`tests/integration_review_gating_http.nim`, which uses real localhost HTTP/MCP
without provider calls and shuts down its owned server thread. The 22 merge-gate
cases include an exception, failures after either approval action, cancellation,
invalid verdicts, stale and cross-session verdicts, and both successful approvals.
Provider integration and E2E suites were intentionally not run for this repair.
Publishing uses `[skip ci]` because master pushes otherwise start paid-provider
workflows; it does not change those workflows or skip any local unit tests.

Source coverage:

| Source | Missing verdict | Reviewer fails after approval |
| --- | --- | --- |
| Historical NAS checkout `19a5c2c` | Defaults to approval; unsafe | Unsafe |
| Published `v20.0.2` / assigned `cf2498b` | Rejects | Could merge; unsafe |
| `v20.0.3`, based on current master `de519b0` | Rejects | Rejects |

Historical release tags and active conversations must be preserved. Updating
source alone does not update existing binaries or container images: rebuild or
install 20.0.3 before starting an orchestrator from an older installation.
