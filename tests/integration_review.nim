## Tests for review agent prompt building, feedback truncation, and progress-based stall detection.

import
  std/[json, os, osproc, sequtils, strformat, strutils, tables, tempfiles, unittest],
  scriptorium/[agent_runner, config, init, logging, orchestrator, ticket_metadata],
  helpers

suite "buildReviewAgentPrompt":
  test "contains expected sections":
    ## Verify the rendered prompt includes ticket, diff, area, summary, agents, and spec sections.
    let prompt = buildReviewAgentPrompt(
      "Fix the login bug",
      "--- a/login.nim\n+++ b/login.nim\n@@ -1 +1 @@\n-old\n+new",
      "area: auth\nResponsible for authentication flows.",
      "Fixed the login validation logic.",
      "Use camelCase naming.",
      "## Auth\nHandles login flows.",
    )
    check "Fix the login bug" in prompt
    check "old" in prompt
    check "new" in prompt
    check "area: auth" in prompt
    check "Fixed the login validation logic" in prompt

  test "contains review instructions and submit_review tool":
    ## Verify the prompt includes review instructions and the submit_review MCP tool.
    let prompt = buildReviewAgentPrompt("ticket", "diff", "area", "summary", "agents", "spec")
    check "submit_review" in prompt
    check "approve" in prompt
    check "request_changes" in prompt

  test "sections are delimited with markdown headers":
    ## Verify each section is labeled with a markdown header for parseability.
    let prompt = buildReviewAgentPrompt("ticket", "diff", "area", "summary", "agents", "spec")
    check "## Ticket Content" in prompt
    check "## Changes" in prompt
    check "## Area Context" in prompt
    check "## Project Conventions (AGENTS.md)" in prompt
    check "## Spec Context" in prompt
    check "## Coding Agent Summary" in prompt
    check "## Instructions" in prompt

  test "empty diff does not crash":
    ## Verify the prompt builder handles an empty diff gracefully.
    let prompt = buildReviewAgentPrompt("ticket", "", "area", "summary", "agents", "spec")
    check "## Changes" in prompt
    check "## Ticket Content" in prompt

  test "whitespace-only diff handled gracefully":
    ## Verify the prompt builder handles a whitespace-only diff.
    let prompt = buildReviewAgentPrompt("ticket", "   \n  \n", "area", "summary", "agents", "spec")
    check "## Changes" in prompt

  test "agents and spec content appear in rendered prompt":
    ## Verify that AGENTS.md and spec content are included in the rendered prompt.
    let prompt = buildReviewAgentPrompt(
      "ticket", "diff", "area", "summary",
      "Always use PascalCase for constants.",
      "## Review Agent\nSection 9 compliance rules.",
    )
    check "Always use PascalCase for constants." in prompt
    check "Section 9 compliance rules." in prompt

suite "review feedback truncation":
  setup:
    discard consumeReviewDecision()

  test "feedback under limit passes through unchanged":
    ## Verify feedback well under ReviewFeedbackMaxBytes is stored verbatim.
    let feedback = 'a'.repeat(100)
    recordReviewDecision("approve", feedback)
    let decision = consumeReviewDecision()
    check decision.feedback == feedback
    check decision.feedback.len == 100

  test "feedback exactly at limit passes through unchanged":
    ## Verify feedback exactly at ReviewFeedbackMaxBytes is stored verbatim.
    let feedback = 'b'.repeat(ReviewFeedbackMaxBytes)
    recordReviewDecision("approve", feedback)
    let decision = consumeReviewDecision()
    check decision.feedback == feedback
    check decision.feedback.len == ReviewFeedbackMaxBytes

  test "feedback one byte over limit is truncated with marker":
    ## Verify feedback at 4097 bytes is truncated with the truncation marker.
    let feedback = 'c'.repeat(ReviewFeedbackMaxBytes + 1)
    recordReviewDecision("approve", feedback)
    let decision = consumeReviewDecision()
    check decision.feedback.len == ReviewFeedbackMaxBytes
    check decision.feedback.endsWith(ReviewTruncationMarker)
    let expectedText = 'c'.repeat(ReviewFeedbackMaxBytes - ReviewTruncationMarker.len)
    check decision.feedback == expectedText & ReviewTruncationMarker

  test "large feedback is truncated with marker":
    ## Verify feedback at 2x the limit is truncated to ReviewFeedbackMaxBytes with marker.
    let feedback = 'd'.repeat(ReviewFeedbackMaxBytes * 2)
    recordReviewDecision("request_changes", feedback)
    let decision = consumeReviewDecision()
    check decision.feedback.len == ReviewFeedbackMaxBytes
    check decision.feedback.endsWith(ReviewTruncationMarker)

suite "progress-based stall detection":
  test "progress timeout triggers stall continuation flow":
    ## When the agent returns with timeoutKind="progress", it should be treated
    ## as a stall and retried with a continuation prompt.
    let tmp = getTempDir() / "scriptorium_test_progress_stall"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0080-progress.md", "# Ticket 80\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 950)

    let assignment = assignOldestOpenTicket(tmp, PlanCallerCli)
    writeFile(assignment.worktree / "Makefile", "test:\n\t@echo OK\nintegration-test:\n\t@echo OK\n")

    var callCount = 0
    var capturedRequests: seq[AgentRunRequest]
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      inc callCount
      capturedRequests.add(request)
      if callCount == 2:
        callSubmitPrTool("progress stall fixed")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: if callCount == 1: 137 else: 0,
        attempt: callCount,
        attemptCount: 1,
        stdout: "reasoning output...",
        lastMessage: "stuck in a loop",
        timeoutKind: if callCount == 1: "progress" else: "none",
      )

    discard executeAssignedTicket(tmp, PlanCallerCli, assignment, fakeRunner)

    check callCount == 2
    check capturedRequests.len == 2
    let retryPrompt = capturedRequests[1].prompt
    check "Ticket 80" in retryPrompt

  test "progress timeout reopens ticket after maxAttempts exhausted":
    ## When the agent repeatedly hits progress timeout and exhausts all attempts,
    ## the ticket should be reopened with timeout_progress failure reason.
    let tmp = getTempDir() / "scriptorium_test_progress_exhaust"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0081-progress-exhaust.md", "# Ticket 81\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 951)

    let assignment = assignOldestOpenTicket(tmp, PlanCallerCli)
    writeFile(assignment.worktree / "Makefile", "test:\n\t@echo OK\nintegration-test:\n\t@echo OK\n")
    let before = planCommitCount(tmp)

    var callCount = 0
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      inc callCount
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 137,
        attempt: callCount,
        attemptCount: 1,
        stdout: "reasoning output...",
        lastMessage: "still stuck",
        timeoutKind: "progress",
      )

    discard executeAssignedTicket(tmp, PlanCallerCli, assignment, fakeRunner)

    let after = planCommitCount(tmp)
    check after > before
    let files = planTreeFiles(tmp)
    check "tickets/open/0081-progress-exhaust.md" in files
    check "tickets/in-progress/0081-progress-exhaust.md" notin files

  test "progressTimeoutMs is passed through to agent request":
    ## Verify that the config value for codingAgentProgressTimeoutMs is
    ## passed through to the AgentRunRequest.
    let tmp = getTempDir() / "scriptorium_test_progress_config"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0082-progress-cfg.md", "# Ticket 82\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 952)

    let assignment = assignOldestOpenTicket(tmp, PlanCallerCli)
    writeFile(assignment.worktree / "Makefile", "test:\n\t@echo OK\nintegration-test:\n\t@echo OK\n")

    var capturedRequest: AgentRunRequest
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      capturedRequest = request
      callSubmitPrTool("progress config check done")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        lastMessage: "done",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, PlanCallerCli, assignment, fakeRunner)

    check capturedRequest.progressTimeoutMs == 600_000
