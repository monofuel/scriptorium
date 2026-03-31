## Integration tests for orchestrator merge-queue flows on local fixture repositories.

import
  std/[os, osproc, sequtils, strformat, strutils, tempfiles, unittest],
  scriptorium/[agent_runner, config, orchestrator],
  helpers

const
  OrchestratorBasePort = 18000

proc writeOrchestratorEndpointConfig(repoPath: string, portOffset: int) =
  ## Write a unique local orchestrator endpoint configuration for test isolation.
  let basePort = OrchestratorBasePort + (getCurrentProcessId().int mod 1000)
  let orchestratorPort = basePort + portOffset
  var cfg = defaultConfig()
  cfg.endpoints.local = &"http://127.0.0.1:{orchestratorPort}"
  writeScriptoriumConfig(repoPath, cfg)

suite "integration orchestrator merge queue":
  setup:
    tickSleepOverrideMs = 0

  teardown:
    tickSleepOverrideMs = -1

  test "IT-02 queue success moves ticket to done and merges ticket commit to master":
    withInitializedTempRepo("scriptorium_integration_it02_", proc(repoPath: string) =
      addPassingMakefile(repoPath)
      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

      let assignment = assignOldestOpenTicket(repoPath)
      writeFile(assignment.worktree / "ticket-output.txt", "done\n")
      runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add ticket-output.txt")
      runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m integration-ticket-output")
      let (ticketHead, ticketHeadRc) = execCmdEx("git -C " & quoteShell(assignment.worktree) & " rev-parse HEAD")
      doAssert ticketHeadRc == 0

      discard enqueueMergeRequest(repoPath, assignment, "merge me")

      let processed = processMergeQueue(repoPath, noopRunner)
      check processed
      check pendingQueueFiles(repoPath).len == 0

      let files = planTreeFiles(repoPath)
      check "tickets/done/0001-first.md" in files
      check "tickets/in-progress/0001-first.md" notin files

      let (masterFile, masterFileRc) = execCmdEx("git -C " & quoteShell(repoPath) & " show master:ticket-output.txt")
      check masterFileRc == 0
      check masterFile.strip() == "done"

      let (_, ancestorRc) = execCmdEx(
        "git -C " & quoteShell(repoPath) & " merge-base --is-ancestor " & ticketHead.strip() & " master"
      )
      check ancestorRc == 0
    )

  test "IT-03 queue failure reopens ticket and appends failure note":
    withInitializedTempRepo("scriptorium_integration_it03_", proc(repoPath: string) =
      addFailingMakefile(repoPath)
      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

      let assignment = assignOldestOpenTicket(repoPath)
      discard enqueueMergeRequest(repoPath, assignment, "expected failure")

      let processed = processMergeQueue(repoPath, noopRunner)
      check processed
      check pendingQueueFiles(repoPath).len == 0

      let files = planTreeFiles(repoPath)
      check "tickets/open/0001-first.md" in files
      check "tickets/in-progress/0001-first.md" notin files

      let ticketContent = readPlanFile(repoPath, "tickets/open/0001-first.md")
      check "## Merge Queue Failure" in ticketContent
      check "- Summary: expected failure" in ticketContent
      check "FAIL" in ticketContent
    )

  test "IT-03b queue failure when integration-test fails reopens ticket":
    withInitializedTempRepo("scriptorium_integration_it03b_", proc(repoPath: string) =
      addIntegrationFailingMakefile(repoPath)
      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

      let assignment = assignOldestOpenTicket(repoPath)
      discard enqueueMergeRequest(repoPath, assignment, "integration failure")

      let processed = processMergeQueue(repoPath, noopRunner)
      check processed
      check pendingQueueFiles(repoPath).len == 0

      let files = planTreeFiles(repoPath)
      check "tickets/open/0001-first.md" in files
      check "tickets/in-progress/0001-first.md" notin files

      let ticketContent = readPlanFile(repoPath, "tickets/open/0001-first.md")
      check "## Merge Queue Failure" in ticketContent
      check "- Summary: integration failure" in ticketContent
      check "make integration-test" in ticketContent
      check "FAIL integration-test" in ticketContent
    )

  test "IT-04 single-flight queue processing keeps second item pending":
    withInitializedTempRepo("scriptorium_integration_it04_", proc(repoPath: string) =
      addPassingMakefile(repoPath)
      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
      addTicketToPlan(repoPath, "open", "0002-second.md", "# Ticket 2\n\n**Area:** b\n")

      let firstAssignment = assignOldestOpenTicket(repoPath)
      let secondAssignment = assignOldestOpenTicket(repoPath)
      discard enqueueMergeRequest(repoPath, firstAssignment, "first summary")
      discard enqueueMergeRequest(repoPath, secondAssignment, "second summary")

      let processed = processMergeQueue(repoPath, noopRunner)
      check processed

      let files = planTreeFiles(repoPath)
      check "tickets/done/0001-first.md" in files
      check "tickets/in-progress/0002-second.md" in files

      let queueFiles = pendingQueueFiles(repoPath)
      check queueFiles.len == 1
      check queueFiles[0] == "queue/merge/pending/0002-0002.md"
    )

  test "IT-05 merge conflict during merge master into ticket reopens ticket":
    withInitializedTempRepo("scriptorium_integration_it05_", proc(repoPath: string) =
      addPassingMakefile(repoPath)

      writeFile(repoPath / "conflict.txt", "line=base\n")
      runCmdOrDie("git -C " & quoteShell(repoPath) & " add conflict.txt")
      runCmdOrDie("git -C " & quoteShell(repoPath) & " commit -m integration-add-conflict-base")

      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
      let assignment = assignOldestOpenTicket(repoPath)

      writeFile(assignment.worktree / "conflict.txt", "line=ticket\n")
      runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add conflict.txt")
      runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m integration-ticket-conflict-change")

      writeFile(repoPath / "conflict.txt", "line=master\n")
      runCmdOrDie("git -C " & quoteShell(repoPath) & " add conflict.txt")
      runCmdOrDie("git -C " & quoteShell(repoPath) & " commit -m integration-master-conflict-change")

      discard enqueueMergeRequest(repoPath, assignment, "conflict expected")

      let processed = processMergeQueue(repoPath, noopRunner)
      check processed
      check pendingQueueFiles(repoPath).len == 0

      let files = planTreeFiles(repoPath)
      check "tickets/open/0001-first.md" in files
      check "tickets/in-progress/0001-first.md" notin files

      let ticketContent = readPlanFile(repoPath, "tickets/open/0001-first.md")
      check "## Merge Queue Failure" in ticketContent
      check "- Summary: conflict expected" in ticketContent
      check "CONFLICT" in ticketContent
    )

  test "IT-08 recovery after partial queue transition converges without duplicate moves":
    withInitializedTempRepo("scriptorium_integration_it08_", proc(repoPath: string) =
      addPassingMakefile(repoPath)
      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

      let assignment = assignOldestOpenTicket(repoPath)
      discard enqueueMergeRequest(repoPath, assignment, "recover me")
      moveTicketStateInPlan(repoPath, "in-progress", "done", "0001-first.md")
      writeActiveQueueInPlan(repoPath, "queue/merge/pending/0001-0001.md\n")

      let firstProcessed = processMergeQueue(repoPath, noopRunner)
      let secondProcessed = processMergeQueue(repoPath, noopRunner)
      check firstProcessed
      check not secondProcessed

      let files = planTreeFiles(repoPath)
      check "tickets/done/0001-first.md" in files
      check "tickets/open/0001-first.md" notin files
      check "tickets/in-progress/0001-first.md" notin files
      check pendingQueueFiles(repoPath).len == 0

      let activeFile = readPlanFile(repoPath, "queue/merge/active.md")
      check activeFile.strip().len == 0
    )

  test "IT-09 red master blocks assignment of open tickets":
    withInitializedTempRepo("scriptorium_integration_it09_", proc(repoPath: string) =
      addFailingMakefile(repoPath)
      writeSpecInPlan(repoPath, "# Spec\n\nNeed assignment.\n")
      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
      writeOrchestratorEndpointConfig(repoPath, 1)

      runOrchestratorForTicks(repoPath, 1, noopRunner)

      let files = planTreeFiles(repoPath)
      check "tickets/open/0001-first.md" in files
      check "tickets/in-progress/0001-first.md" notin files
    )

  test "IT-10 global halt while red resumes after master health is restored":
    withInitializedTempRepo("scriptorium_integration_it10_", proc(repoPath: string) =
      addPassingMakefile(repoPath)
      writeSpecInPlan(repoPath, "# Spec\n\nNeed queue processing.\n")
      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

      let assignment = assignOldestOpenTicket(repoPath)
      writeFile(assignment.worktree / "ticket-output.txt", "done\n")
      runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add ticket-output.txt")
      runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m integration-ticket-output")
      discard enqueueMergeRequest(repoPath, assignment, "merge me")

      addFailingMakefile(repoPath)
      writeOrchestratorEndpointConfig(repoPath, 2)
      runOrchestratorForTicks(repoPath, 1, noopRunner)

      var files = planTreeFiles(repoPath)
      check "tickets/in-progress/0001-first.md" in files
      check "tickets/done/0001-first.md" notin files
      check pendingQueueFiles(repoPath).len == 1

      addPassingMakefile(repoPath)
      runOrchestratorForTicks(repoPath, 1, noopRunner)

      files = planTreeFiles(repoPath)
      check "tickets/done/0001-first.md" in files
      check "tickets/in-progress/0001-first.md" notin files
      check pendingQueueFiles(repoPath).len == 0
    )

  test "IT-11 integration-test failure on master blocks assignment of open tickets":
    withInitializedTempRepo("scriptorium_integration_it11_", proc(repoPath: string) =
      addIntegrationFailingMakefile(repoPath)
      writeSpecInPlan(repoPath, "# Spec\n\nNeed assignment.\n")
      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
      writeOrchestratorEndpointConfig(repoPath, 3)

      runOrchestratorForTicks(repoPath, 1, noopRunner)

      let files = planTreeFiles(repoPath)
      check "tickets/open/0001-first.md" in files
      check "tickets/in-progress/0001-first.md" notin files
    )
