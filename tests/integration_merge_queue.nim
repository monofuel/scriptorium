## Tests for MCP tools, coding agent execution, and merge queue.

import
  std/[algorithm, json, locks, os, osproc, sequtils, sha1, strformat, strutils, tables, tempfiles, times, unittest],
  jsony,
  scriptorium/[agent_runner, config, init, logging, orchestrator, ticket_metadata],
  helpers

suite "orchestrator mcp tools":
  test "createOrchestratorServer registers submit_pr and consumeSubmitPrSummary clears state":
    discard consumeSubmitPrSummary()
    let httpServer = createOrchestratorServer()

    check httpServer.server.tools.hasKey("submit_pr")
    check httpServer.server.toolHandlers.hasKey("submit_pr")
    let submitPrHandler = httpServer.server.toolHandlers["submit_pr"]
    let toolResponse = submitPrHandler(%*{"summary": "ship tool"})
    check toolResponse.getStr() == "Merge request enqueued."
    check consumeSubmitPrSummary() == "ship tool"
    check consumeSubmitPrSummary() == ""

  test "submit_review tool is registered and handler stores decision":
    discard consumeReviewDecision()
    let httpServer = createOrchestratorServer()

    check httpServer.server.tools.hasKey("submit_review")
    check httpServer.server.toolHandlers.hasKey("submit_review")
    let reviewHandler = httpServer.server.toolHandlers["submit_review"]
    let approveResponse = reviewHandler(%*{"action": "approve"})
    check approveResponse.getStr() == "Review decision recorded."
    let decision = consumeReviewDecision()
    check decision.action == "approve"
    check decision.feedback == ""
    check consumeReviewDecision().action == ""

    let changesResponse = reviewHandler(%*{"action": "request_changes", "feedback": "fix the tests"})
    check changesResponse.getStr() == "Review decision recorded."
    let decision2 = consumeReviewDecision()
    check decision2.action == "request_changes"
    check decision2.feedback == "fix the tests"

  test "submit_review rejects request_changes without feedback":
    let httpServer = createOrchestratorServer()
    let reviewHandler = httpServer.server.toolHandlers["submit_review"]
    let response = reviewHandler(%*{"action": "request_changes"})
    check "Feedback is required" in response.getStr()
    check consumeReviewDecision().action == ""

  test "submit_review rejects invalid action":
    let httpServer = createOrchestratorServer()
    let reviewHandler = httpServer.server.toolHandlers["submit_review"]
    let response = reviewHandler(%*{"action": "reject"})
    check "Invalid action" in response.getStr()
    check consumeReviewDecision().action == ""

  test "submit_pr enqueues immediately with active worktree":
    discard consumeSubmitPrSummary()
    let tmp = getTempDir() / "scriptorium_test_submit_pr_pass"
    createDir(tmp)
    defer: removeDir(tmp)
    writeFile(tmp / "Makefile", "test:\n\t@echo PASS test\nintegration-test:\n\t@echo PASS integration-test\n")
    setActiveTicketWorktree(tmp, "0099")
    defer: clearActiveTicketWorktree()

    let httpServer = createOrchestratorServer()
    let submitPrHandler = httpServer.server.toolHandlers["submit_pr"]
    let toolResponse = submitPrHandler(%*{"summary": "tests pass"})
    check toolResponse.getStr() == "Merge request enqueued."
    check consumeSubmitPrSummary() == "tests pass"

  test "submit_pr enqueues even when tests would fail (merge queue is the gate)":
    discard consumeSubmitPrSummary()
    let tmp = getTempDir() / "scriptorium_test_submit_pr_fail"
    createDir(tmp)
    defer: removeDir(tmp)
    writeFile(tmp / "Makefile", "test:\n\t@echo FAIL test\n\t@false\n")
    setActiveTicketWorktree(tmp, "0099")
    defer: clearActiveTicketWorktree()

    let httpServer = createOrchestratorServer()
    let submitPrHandler = httpServer.server.toolHandlers["submit_pr"]
    let toolResponse = submitPrHandler(%*{"summary": "tests fail"})
    check toolResponse.getStr() == "Merge request enqueued."
    check consumeSubmitPrSummary() == "tests fail"

suite "orchestrator coding agent execution":
  test "executeAssignedTicket runs agent and appends run summary":
    let tmp = getTempDir() / "scriptorium_test_execute_assigned_ticket"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
    var writtenCfg = defaultConfig()
    writtenCfg.agents.coding.reasoningEffort = "high"
    writtenCfg.endpoints.local = "http://127.0.0.1:19042"
    writtenCfg.timeouts.codingAgentMaxAttempts = 2
    writeScriptoriumConfig(tmp, writtenCfg)

    let assignment = assignOldestOpenTicket(tmp)
    let before = planCommitCount(tmp)

    var callCount = 0
    var capturedRequest = AgentRunRequest()
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Capture one request and return a deterministic successful run result.
      inc callCount
      capturedRequest = request
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        stdout: toJson(StreamMessageJson(`type`: "message", text: "done")),
        logFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.jsonl",
        lastMessageFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.last_message.txt",
        lastMessage: "Implemented the ticket.",
        timeoutKind: "none",
      )

    let runResult = executeAssignedTicket(tmp, assignment, fakeRunner)
    let after = planCommitCount(tmp)

    check callCount == 2
    check capturedRequest.model == "claude-sonnet-4-6"
    check capturedRequest.reasoningEffort == "high"
    check capturedRequest.mcpEndpoint == "http://127.0.0.1:19042"
    check capturedRequest.workingDir == assignment.worktree
    check capturedRequest.ticketId == "0001"
    check "Ticket 1" in capturedRequest.prompt
    check tmp in capturedRequest.prompt
    check "AGENTS.md" in capturedRequest.prompt
    check "Active working directory path (this is the ticket worktree and active repository checkout for this task):" in capturedRequest.prompt
    check "Treat this working directory as the repository checkout for code edits, builds, tests, and commits." in capturedRequest.prompt
    check runResult.exitCode == 0
    check after == before + 5

    let (ticketContent, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/open/0001-first.md"
    )
    check ticketRc == 0
    check "## Agent Run" in ticketContent
    check "- Model: claude-sonnet-4-6" in ticketContent
    check "- Exit Code: 0" in ticketContent

    let commits = latestPlanCommits(tmp, 4)
    check commits[1].startsWith("scriptorium: reopen failed ticket")
    check "scriptorium: record agent run 0001-first" in commits[3]

  test "executeAssignedTicket enqueues merge request from submit_pr MCP tool":
    let tmp = getTempDir() / "scriptorium_test_execute_assigned_enqueue"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    let before = planCommitCount(tmp)
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Return a deterministic run result and signal completion with submit_pr.
      discard request
      callSubmitPrTool("ship it")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        logFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.jsonl",
        lastMessageFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.last_message.txt",
        lastMessage: "Work complete.",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunner)
    let after = planCommitCount(tmp)
    let files = planTreeFiles(tmp)

    check after == before + 4
    check "queue/merge/pending/0001-0001.md" in files
    let (queueEntry, queueRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:queue/merge/pending/0001-0001.md"
    )
    check queueRc == 0
    check "**Summary:** ship it" in queueEntry
    check "**Branch:** scriptorium/ticket-0001" in queueEntry

  test "executeAssignedTicket wires onEvent callback that accepts all event kinds":
    let tmp = getTempDir() / "scriptorium_test_execute_on_event"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    var capturedRequest = AgentRunRequest()
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Capture the request to inspect the onEvent callback.
      capturedRequest = request
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        logFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.jsonl",
        lastMessageFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.last_message.txt",
        lastMessage: "done",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunner)

    check capturedRequest.onEvent != nil

    let allKinds = [
      agentEventTool,
      agentEventStatus,
      agentEventHeartbeat,
      agentEventReasoning,
      agentEventMessage,
    ]
    for kind in allKinds:
      capturedRequest.onEvent(AgentStreamEvent(kind: kind, text: "test", rawLine: ""))

suite "orchestrator merge queue":
  test "ensureMergeQueueInitialized is idempotent":
    let tmp = getTempDir() / "scriptorium_test_merge_queue_init"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    let before = planCommitCount(tmp)
    let first = ensureMergeQueueInitialized(tmp)
    let afterFirst = planCommitCount(tmp)
    let second = ensureMergeQueueInitialized(tmp)
    let afterSecond = planCommitCount(tmp)
    let files = planTreeFiles(tmp)

    check first
    check not second
    check afterFirst == before + 1
    check afterSecond == afterFirst
    check "queue/merge/pending/.gitkeep" in files
    check "queue/merge/active.md" in files

  test "processMergeQueue handles one item per call":
    let tmp = getTempDir() / "scriptorium_test_merge_queue_single_flight"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** b\n")

    let firstAssignment = assignOldestOpenTicket(tmp)
    let secondAssignment = assignOldestOpenTicket(tmp)
    discard enqueueMergeRequest(tmp, firstAssignment, "first summary")
    discard enqueueMergeRequest(tmp, secondAssignment, "second summary")

    let processed = processMergeQueue(tmp, noopRunner)
    let files = planTreeFiles(tmp)
    let queueFiles = files.filterIt(it.startsWith("queue/merge/pending/") and it.endsWith(".md"))

    check processed
    check "tickets/done/0001-first.md" in files
    check "tickets/in-progress/0002-second.md" in files
    check queueFiles.len == 1
    check queueFiles[0] == "queue/merge/pending/0002-0002.md"

  test "processMergeQueue success path merges to master and moves ticket to done":
    let tmp = getTempDir() / "scriptorium_test_merge_queue_success"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "ticket-output.txt", "done\n")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add ticket-output.txt")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m ticket-output")
    discard enqueueMergeRequest(tmp, assignment, "merge me")

    let processed = processMergeQueue(tmp, noopRunner)
    let files = planTreeFiles(tmp)
    check processed
    check "tickets/done/0001-first.md" in files
    check "queue/merge/pending/0001-0001.md" notin files

    let (masterFile, masterRc) = execCmdEx("git -C " & quoteShell(tmp) & " show master:ticket-output.txt")
    check masterRc == 0
    check masterFile.strip() == "done"

    let (ticketContent, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/done/0001-first.md"
    )
    check ticketRc == 0
    check "## Merge Queue Success" in ticketContent

  test "processMergeQueue failure path reopens ticket with failure note":
    let tmp = getTempDir() / "scriptorium_test_merge_queue_failure"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addFailingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    discard enqueueMergeRequest(tmp, assignment, "expected failure")
    let processed = processMergeQueue(tmp, noopRunner)
    let files = planTreeFiles(tmp)

    check processed
    check "tickets/open/0001-first.md" in files
    check "tickets/in-progress/0001-first.md" notin files
    check "queue/merge/pending/0001-0001.md" notin files

    let (ticketContent, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/open/0001-first.md"
    )
    check ticketRc == 0
    check "## Merge Queue Failure" in ticketContent

  test "processMergeQueue failure path reopens ticket when integration-test fails":
    let tmp = getTempDir() / "scriptorium_test_merge_queue_integration_failure"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addIntegrationFailingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    discard enqueueMergeRequest(tmp, assignment, "integration failure")
    let processed = processMergeQueue(tmp, noopRunner)
    let files = planTreeFiles(tmp)

    check processed
    check "tickets/open/0001-first.md" in files
    check "tickets/in-progress/0001-first.md" notin files
    check "queue/merge/pending/0001-0001.md" notin files

    let (ticketContent, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/open/0001-first.md"
    )
    check ticketRc == 0
    check "## Merge Queue Failure" in ticketContent
    check "make integration-test" in ticketContent
    check "FAIL integration-test" in ticketContent

  test "processMergeQueue review approve proceeds to merge":
    let tmp = getTempDir() / "scriptorium_test_review_approve"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "ticket-output.txt", "done\n")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add ticket-output.txt")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m ticket-output")
    discard enqueueMergeRequest(tmp, assignment, "approve me")

    proc approveRunner(request: AgentRunRequest): AgentRunResult =
      ## Fake runner that records an approve decision.
      discard request
      recordReviewDecision("approve", "")
      AgentRunResult(exitCode: 0, backend: harnessCodex, timeoutKind: "none")

    discard consumeReviewDecision()
    let processed = processMergeQueue(tmp, approveRunner)
    check processed

    let files = planTreeFiles(tmp)
    check "tickets/done/0001-first.md" in files
    check "tickets/in-progress/0001-first.md" notin files

    let (ticketContent, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/done/0001-first.md"
    )
    check ticketRc == 0
    check "**Review:** approved" in ticketContent

  test "processMergeQueue review request_changes reopens ticket":
    let tmp = getTempDir() / "scriptorium_test_review_changes"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "ticket-output.txt", "done\n")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add ticket-output.txt")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m ticket-output")
    discard enqueueMergeRequest(tmp, assignment, "needs changes")

    proc changesRunner(request: AgentRunRequest): AgentRunResult =
      ## Fake runner that records a request_changes decision.
      discard request
      recordReviewDecision("request_changes", "fix the formatting")
      AgentRunResult(exitCode: 0, backend: harnessCodex, timeoutKind: "none")

    discard consumeReviewDecision()
    let processed = processMergeQueue(tmp, changesRunner)
    check processed

    let files = planTreeFiles(tmp)
    check "tickets/open/0001-first.md" in files
    check "tickets/in-progress/0001-first.md" notin files
    check "tickets/done/0001-first.md" notin files

    let (ticketContent, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/open/0001-first.md"
    )
    check ticketRc == 0
    check "**Review:** changes requested" in ticketContent
    check "**Review Feedback:** fix the formatting" in ticketContent

  test "processMergeQueue review stall defaults to approve":
    let tmp = getTempDir() / "scriptorium_test_review_stall"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "ticket-output.txt", "done\n")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add ticket-output.txt")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m ticket-output")
    discard enqueueMergeRequest(tmp, assignment, "stall test")

    discard consumeReviewDecision()
    let processed = processMergeQueue(tmp, noopRunner)
    check processed

    let files = planTreeFiles(tmp)
    check "tickets/done/0001-first.md" in files
    check "tickets/in-progress/0001-first.md" notin files

    let (ticketContent, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/done/0001-first.md"
    )
    check ticketRc == 0
    check "**Review:** approved" in ticketContent

  test "processMergeQueue review captures reasoning from message events":
    let tmp = getTempDir() / "scriptorium_test_review_reasoning"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "ticket-output.txt", "done\n")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add ticket-output.txt")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m ticket-output")
    discard enqueueMergeRequest(tmp, assignment, "reasoning test")

    proc reasoningRunner(request: AgentRunRequest): AgentRunResult =
      ## Fake runner that emits message events and records an approve decision.
      if not request.onEvent.isNil:
        request.onEvent(AgentStreamEvent(kind: agentEventMessage, text: "The code looks correct."))
        request.onEvent(AgentStreamEvent(kind: agentEventMessage, text: "All tests pass and naming is consistent."))
        request.onEvent(AgentStreamEvent(kind: agentEventTool, text: "submit_review"))
      recordReviewDecision("approve", "")
      AgentRunResult(exitCode: 0, backend: harnessCodex, timeoutKind: "none")

    discard consumeReviewDecision()
    let processed = processMergeQueue(tmp, reasoningRunner)
    check processed

    let (ticketContent, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/done/0001-first.md"
    )
    check ticketRc == 0
    check "**Review:** approved" in ticketContent
    check "**Review Reasoning:**" in ticketContent
    check "The code looks correct." in ticketContent
    check "All tests pass and naming is consistent." in ticketContent

  test "processMergeQueue review truncates long reasoning":
    let tmp = getTempDir() / "scriptorium_test_review_reasoning_truncate"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "ticket-output.txt", "done\n")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add ticket-output.txt")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m ticket-output")
    discard enqueueMergeRequest(tmp, assignment, "truncate test")

    let longText = "x".repeat(3000)
    proc longReasoningRunner(request: AgentRunRequest): AgentRunResult =
      ## Fake runner that emits a very long message event.
      if not request.onEvent.isNil:
        request.onEvent(AgentStreamEvent(kind: agentEventMessage, text: longText))
      recordReviewDecision("approve", "")
      AgentRunResult(exitCode: 0, backend: harnessCodex, timeoutKind: "none")

    discard consumeReviewDecision()
    let processed = processMergeQueue(tmp, longReasoningRunner)
    check processed

    let (ticketContent, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/done/0001-first.md"
    )
    check ticketRc == 0
    check "**Review Reasoning:**" in ticketContent
    check longText notin ticketContent

  test "executeAssignedTicket auto-commits dirty worktree before enqueue":
    let tmp = getTempDir() / "scriptorium_test_autocommit_dirty_worktree"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Write a file but do not commit, then signal submit_pr.
      discard request
      writeFile(assignment.worktree / "uncommitted.txt", "dirty\n")
      callSubmitPrTool("auto-commit test")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        logFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.jsonl",
        lastMessageFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.last_message.txt",
        lastMessage: "done",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunner)

    let (statusOutput, statusRc) = execCmdEx("git -C " & quoteShell(assignment.worktree) & " status --porcelain")
    check statusRc == 0
    check statusOutput.strip().len == 0

    let queueFiles = pendingQueueFiles(tmp)
    check queueFiles.len == 1

  test "processMergeQueue auto-commits dirty worktree before merge":
    let tmp = getTempDir() / "scriptorium_test_merge_queue_autocommit"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "uncommitted.txt", "dirty\n")
    discard enqueueMergeRequest(tmp, assignment, "dirty merge")

    let processed = processMergeQueue(tmp, noopRunner)
    let files = planTreeFiles(tmp)
    check processed
    check "tickets/done/0001-first.md" in files

    let (masterFile, masterRc) = execCmdEx("git -C " & quoteShell(tmp) & " show master:uncommitted.txt")
    check masterRc == 0
    check masterFile.strip() == "dirty"

  test "processMergeQueue parks ticket after MaxMergeFailures":
    let tmp = getTempDir() / "scriptorium_test_merge_queue_stuck"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addFailingMakefile(tmp)

    let priorFailures = "## Merge Queue Failure\n\nfail 1\n\n## Merge Queue Failure\n\nfail 2\n"
    let ticketContent = "# Ticket 1\n\n**Area:** a\n\n" & priorFailures
    addTicketToPlan(tmp, "open", "0001-first.md", ticketContent)

    let assignment = assignOldestOpenTicket(tmp)
    discard enqueueMergeRequest(tmp, assignment, "expected stuck")
    let processed = processMergeQueue(tmp, noopRunner)
    let files = planTreeFiles(tmp)

    check processed
    check "tickets/stuck/0001-first.md" in files
    check "tickets/open/0001-first.md" notin files
    check "tickets/in-progress/0001-first.md" notin files

    let (ticketOut, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/stuck/0001-first.md"
    )
    check ticketRc == 0
    check ticketOut.count("## Merge Queue Failure") == 3

    let commits = latestPlanCommits(tmp, 2)
    check commits.len > 1
    check "scriptorium: park stuck ticket 0001" in commits[1]

  test "stuck tickets excluded from areasNeedingTickets":
    let tmp = getTempDir() / "scriptorium_test_stuck_areas_excluded"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addAreaToPlan(tmp, "01-cli.md", "# Area 01\n")
    addAreaToPlan(tmp, "02-core.md", "# Area 02\n")
    addTicketToPlan(tmp, "stuck", "0001-cli-ticket.md", "# Ticket\n\n**Area:** 01-cli\n")

    let needed = areasNeedingTickets(tmp)
    check "areas/02-core.md" in needed
    check "areas/01-cli.md" notin needed

  test "processMergeQueue recovers missing worktree from branch":
    let tmp = getTempDir() / "scriptorium_test_merge_queue_recover_worktree"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "ticket-output.txt", "recovered\n")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add ticket-output.txt")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m ticket-output")
    discard enqueueMergeRequest(tmp, assignment, "recover me")

    # Simulate container restart: remove the worktree directory but keep the branch
    removeDir(assignment.worktree)
    runCmdOrDie("git -C " & quoteShell(tmp) & " worktree prune")

    let processed = processMergeQueue(tmp, noopRunner)
    let files = planTreeFiles(tmp)
    check processed
    check "tickets/done/0001-first.md" in files
    check "queue/merge/pending/0001-0001.md" notin files

    let (masterFile, masterRc) = execCmdEx("git -C " & quoteShell(tmp) & " show master:ticket-output.txt")
    check masterRc == 0
    check masterFile.strip() == "recovered"

  test "processMergeQueue reopens ticket when worktree and branch are both missing":
    let tmp = getTempDir() / "scriptorium_test_merge_queue_no_branch"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    discard enqueueMergeRequest(tmp, assignment, "lost branch")

    # Simulate container restart: remove both worktree and branch
    removeDir(assignment.worktree)
    runCmdOrDie("git -C " & quoteShell(tmp) & " worktree prune")
    runCmdOrDie("git -C " & quoteShell(tmp) & " branch -D " & quoteShell(assignment.branch))

    let processed = processMergeQueue(tmp, noopRunner)
    let files = planTreeFiles(tmp)
    check processed
    check "tickets/open/0001-first.md" in files
    check "tickets/in-progress/0001-first.md" notin files
    check "queue/merge/pending/0001-0001.md" notin files

    let (ticketContent, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/open/0001-first.md"
    )
    check ticketRc == 0
    check "## Merge Queue Failure" in ticketContent
    check "worktree and branch missing" in ticketContent
