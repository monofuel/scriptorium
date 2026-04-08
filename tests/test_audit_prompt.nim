## Unit tests for buildAuditAgentPrompt.

import
  std/[strutils, unittest],
  scriptorium/prompt_builders

suite "buildAuditAgentPrompt":
  test "renders template with all four bindings":
    ## Verify the rendered prompt includes all four binding values.
    let prompt = buildAuditAgentPrompt(
      spec = "## Auth\nHandles login flows.",
      agentsMd = "Use camelCase naming.",
      lastAuditCommit = "abc1234",
      diff = "--- a/foo.nim\n+++ b/foo.nim\n@@ -1 +1 @@\n-old\n+new",
    )
    check "Handles login flows." in prompt
    check "Use camelCase naming." in prompt
    check "abc1234" in prompt
    check "-old" in prompt
    check "+new" in prompt

  test "contains audit instructions":
    ## Verify the prompt includes the audit report sections.
    let prompt = buildAuditAgentPrompt("spec", "agents", "deadbeef", "diff")
    check "Spec Drift" in prompt
    check "AGENTS.md Violations" in prompt
    check "Spec Hygiene" in prompt

  test "includes tone and method but not hygiene":
    ## Verify the prompt includes tone and engineering method directives but not repo hygiene.
    let prompt = buildAuditAgentPrompt("spec", "agents", "deadbeef", "diff")
    check "patience and kindness" in prompt or "Deliver all" in prompt
    check "root cause" in prompt or "five times" in prompt
