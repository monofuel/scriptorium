## Integration tests for orchestrator merge-queue flows on local fixture repositories.

import
  std/[algorithm, os, osproc, sequtils, strformat, strutils, tempfiles, unittest],
  jsony,
  scriptorium/[config, init, orchestrator]

const
  OrchestratorBasePort = 18000

proc runCmdOrDie(cmd: string) =
  ## Run a shell command and fail immediately when it exits non-zero.
  let (output, rc) = execCmdEx(cmd)
  doAssert rc == 0, cmd & "\n" & output

proc makeTestRepo(path: string) =
  ## Create a minimal git repository at path suitable for integration tests.
  if dirExists(path):
    removeDir(path)
  createDir(path)
  runCmdOrDie("git -C " & quoteShell(path) & " init")
  runCmdOrDie("git -C " & quoteShell(path) & " config user.email test@test.com")
  runCmdOrDie("git -C " & quoteShell(path) & " config user.name Test")
  runCmdOrDie("git -C " & quoteShell(path) & " commit --allow-empty -m initial")

proc withTempRepo(prefix: string, action: proc(repoPath: string)) =
  ## Create a temporary git repository, run action, and clean up afterwards.
  let repoPath = createTempDir(prefix, "", getTempDir())
  defer:
    removeDir(repoPath)
  makeTestRepo(repoPath)
  action(repoPath)

proc withPlanWorktree(repoPath: string, suffix: string, action: proc(planPath: string)) =
  ## Open scriptorium/plan in a temporary worktree for direct fixture mutations.
  let planPath = createTempDir("scriptorium_integration_plan_" & suffix & "_", "", getTempDir())
  removeDir(planPath)
  defer:
    if dirExists(planPath):
      removeDir(planPath)

  runCmdOrDie("git -C " & quoteShell(repoPath) & " worktree add " & quoteShell(planPath) & " scriptorium/plan")
  defer:
    discard execCmdEx("git -C " & quoteShell(repoPath) & " worktree remove --force " & quoteShell(planPath))

  action(planPath)

proc addTicketToPlan(repoPath: string, state: string, fileName: string, content: string) =
  ## Add one ticket markdown file to a state directory and commit it.
  withPlanWorktree(repoPath, "add_ticket", proc(planPath: string) =
    let relPath = "tickets" / state / fileName
    writeFile(planPath / relPath, content)
    runCmdOrDie("git -C " & quoteShell(planPath) & " add " & quoteShell(relPath))
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m integration-add-ticket")
  )

proc addPassingMakefile(repoPath: string) =
  ## Add a passing make target for queue-processing tests.
  writeFile(repoPath / "Makefile", "test:\n\t@echo PASS\n")
  runCmdOrDie("git -C " & quoteShell(repoPath) & " add Makefile")
  runCmdOrDie("git -C " & quoteShell(repoPath) & " commit -m integration-add-passing-makefile")

proc addFailingMakefile(repoPath: string) =
  ## Add a failing make target for queue-processing tests.
  writeFile(repoPath / "Makefile", "test:\n\t@echo FAIL\n\t@false\n")
  runCmdOrDie("git -C " & quoteShell(repoPath) & " add Makefile")
  runCmdOrDie("git -C " & quoteShell(repoPath) & " commit -m integration-add-failing-makefile")

proc planTreeFiles(repoPath: string): seq[string] =
  ## Return tracked file paths from the plan branch tree.
  let (output, rc) = execCmdEx("git -C " & quoteShell(repoPath) & " ls-tree -r --name-only scriptorium/plan")
  doAssert rc == 0
  result = output.splitLines().filterIt(it.len > 0)

proc pendingQueueFiles(repoPath: string): seq[string] =
  ## Return pending merge-queue markdown entries sorted by file name.
  let files = planTreeFiles(repoPath)
  result = files.filterIt(it.startsWith("queue/merge/pending/") and it.endsWith(".md"))
  result.sort()

proc readPlanFile(repoPath: string, relPath: string): string =
  ## Read one file from the plan branch tree.
  let (output, rc) = execCmdEx(
    "git -C " & quoteShell(repoPath) & " show scriptorium/plan:" & relPath
  )
  doAssert rc == 0, relPath
  result = output

proc moveTicketStateInPlan(repoPath: string, fromRelPath: string, toRelPath: string, commitMessage: string) =
  ## Move one ticket between plan state directories and commit the fixture mutation.
  withPlanWorktree(repoPath, "move_ticket_state", proc(planPath: string) =
    moveFile(planPath / fromRelPath, planPath / toRelPath)
    runCmdOrDie("git -C " & quoteShell(planPath) & " add -A tickets")
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m " & quoteShell(commitMessage))
  )

proc writeActiveQueueInPlan(repoPath: string, activeValue: string, commitMessage: string) =
  ## Write queue/merge/active.md and commit it on the plan branch.
  withPlanWorktree(repoPath, "write_active_queue", proc(planPath: string) =
    writeFile(planPath / "queue/merge/active.md", activeValue)
    runCmdOrDie("git -C " & quoteShell(planPath) & " add queue/merge/active.md")
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m " & quoteShell(commitMessage))
  )

proc writeSpecInPlan(repoPath: string, content: string, commitMessage: string) =
  ## Replace spec.md on the plan branch and commit fixture content.
  withPlanWorktree(repoPath, "write_spec", proc(planPath: string) =
    writeFile(planPath / "spec.md", content)
    runCmdOrDie("git -C " & quoteShell(planPath) & " add spec.md")
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m " & quoteShell(commitMessage))
  )

proc writeScriptoriumConfig(repoPath: string, cfg: Config) =
  ## Write one typed scriptorium.json payload for integration test configuration.
  writeFile(repoPath / "scriptorium.json", cfg.toJson())

proc writeOrchestratorEndpointConfig(repoPath: string, portOffset: int) =
  ## Write a unique local orchestrator endpoint configuration for test isolation.
  let basePort = OrchestratorBasePort + (getCurrentProcessId().int mod 1000)
  let orchestratorPort = basePort + portOffset
  var cfg = defaultConfig()
  cfg.endpoints.local = &"http://127.0.0.1:{orchestratorPort}"
  writeScriptoriumConfig(repoPath, cfg)

suite "integration orchestrator merge queue":
  test "IT-02 queue success moves ticket to done and merges ticket commit to master":
    withTempRepo("scriptorium_integration_it02_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      addPassingMakefile(repoPath)
      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

      let assignment = assignOldestOpenTicket(repoPath)
      writeFile(assignment.worktree / "ticket-output.txt", "done\n")
      runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add ticket-output.txt")
      runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m integration-ticket-output")
      let (ticketHead, ticketHeadRc) = execCmdEx("git -C " & quoteShell(assignment.worktree) & " rev-parse HEAD")
      doAssert ticketHeadRc == 0

      discard enqueueMergeRequest(repoPath, assignment, "merge me")

      let processed = processMergeQueue(repoPath)
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
    withTempRepo("scriptorium_integration_it03_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      addFailingMakefile(repoPath)
      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

      let assignment = assignOldestOpenTicket(repoPath)
      discard enqueueMergeRequest(repoPath, assignment, "expected failure")

      let processed = processMergeQueue(repoPath)
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

  test "IT-04 single-flight queue processing keeps second item pending":
    withTempRepo("scriptorium_integration_it04_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      addPassingMakefile(repoPath)
      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
      addTicketToPlan(repoPath, "open", "0002-second.md", "# Ticket 2\n\n**Area:** b\n")

      let firstAssignment = assignOldestOpenTicket(repoPath)
      let secondAssignment = assignOldestOpenTicket(repoPath)
      discard enqueueMergeRequest(repoPath, firstAssignment, "first summary")
      discard enqueueMergeRequest(repoPath, secondAssignment, "second summary")

      let processed = processMergeQueue(repoPath)
      check processed

      let files = planTreeFiles(repoPath)
      check "tickets/done/0001-first.md" in files
      check "tickets/in-progress/0002-second.md" in files

      let queueFiles = pendingQueueFiles(repoPath)
      check queueFiles.len == 1
      check queueFiles[0] == "queue/merge/pending/0002-0002.md"
    )

  test "IT-05 merge conflict during merge master into ticket reopens ticket":
    withTempRepo("scriptorium_integration_it05_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
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

      let processed = processMergeQueue(repoPath)
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
    withTempRepo("scriptorium_integration_it08_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      addPassingMakefile(repoPath)
      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

      let assignment = assignOldestOpenTicket(repoPath)
      discard enqueueMergeRequest(repoPath, assignment, "recover me")
      moveTicketStateInPlan(
        repoPath,
        assignment.inProgressTicket,
        "tickets/done/0001-first.md",
        "integration-partial-done-transition",
      )
      writeActiveQueueInPlan(
        repoPath,
        "queue/merge/pending/0001-0001.md\n",
        "integration-partial-active-state",
      )

      let firstProcessed = processMergeQueue(repoPath)
      let secondProcessed = processMergeQueue(repoPath)
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
    withTempRepo("scriptorium_integration_it09_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      addFailingMakefile(repoPath)
      writeSpecInPlan(repoPath, "# Spec\n\nNeed assignment.\n", "integration-write-spec")
      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
      writeOrchestratorEndpointConfig(repoPath, 1)

      runOrchestratorForTicks(repoPath, 1)

      let files = planTreeFiles(repoPath)
      check "tickets/open/0001-first.md" in files
      check "tickets/in-progress/0001-first.md" notin files
    )

  test "IT-10 global halt while red resumes after master health is restored":
    withTempRepo("scriptorium_integration_it10_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      addPassingMakefile(repoPath)
      writeSpecInPlan(repoPath, "# Spec\n\nNeed queue processing.\n", "integration-write-spec")
      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

      let assignment = assignOldestOpenTicket(repoPath)
      writeFile(assignment.worktree / "ticket-output.txt", "done\n")
      runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add ticket-output.txt")
      runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m integration-ticket-output")
      discard enqueueMergeRequest(repoPath, assignment, "merge me")

      addFailingMakefile(repoPath)
      writeOrchestratorEndpointConfig(repoPath, 2)
      runOrchestratorForTicks(repoPath, 1)

      var files = planTreeFiles(repoPath)
      check "tickets/in-progress/0001-first.md" in files
      check "tickets/done/0001-first.md" notin files
      check pendingQueueFiles(repoPath).len == 1

      addPassingMakefile(repoPath)
      runOrchestratorForTicks(repoPath, 1)

      files = planTreeFiles(repoPath)
      check "tickets/done/0001-first.md" in files
      check "tickets/in-progress/0001-first.md" notin files
      check pendingQueueFiles(repoPath).len == 0
    )

