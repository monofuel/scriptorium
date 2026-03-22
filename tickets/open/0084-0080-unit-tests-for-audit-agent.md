<!-- file: tickets/open/0080-audit-agent-tests.md -->
# 0080 — Unit tests for audit agent

**Area:** audit-agent
**Depends:** 0077

Add unit tests for the audit agent's core logic.

## Details

Create `tests/test_audit_agent.nim`:

1. Test `needsAudit`:
   - Returns `true` when last audited commit differs from current HEAD.
   - Returns `false` when last audited commit matches current HEAD.
   - Returns `true` when no previous audit state exists (first run).

2. Test `loadAuditState` / `saveAuditState` round-trip:
   - Save state, load it back, verify fields match.

3. Test `buildAuditAgentPrompt`:
   - Renders template with all placeholders filled.
   - No unresolved `{{PLACEHOLDER}}` patterns in output.

4. Test audit report filename generation uses correct timestamp format.

Follow existing test patterns in `tests/test_*.nim`. Use `tests/config.nims` for import paths. Do NOT mock external services — these are unit tests for pure logic functions.

Add the test file to the `Makefile` test target if needed.

## Verification

- `make test` passes including the new test file.
- All test cases pass.
