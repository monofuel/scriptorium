## Tests for orchestrator tick flow, concurrent execution, and merge queue ordering.

import
  std/[algorithm, json, locks, os, osproc, sequtils, strutils, tables, tempfiles, times, unittest],
  scriptorium/[agent_pool, agent_runner, config, init, logging, orchestrator, ticket_metadata],
  helpers

suite "orchestrator final v1 flow":
  setup:

    while consumeSubmitPrSummary() != "": discard
    tickSleepOverrideMs = 0

  teardown:
    tickSleepOverrideMs = -1

  test "runOrchestratorForTicks drives spec to done in one bounded tick with mocked runners":
    let tmp = getTempDir() / "scriptorium_test_v1_39_full_cycle_tick"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    writeSpecInPlan(tmp, "# Spec\n\nDeliver one full-flow ticket.\n")
    writeOrchestratorEndpointConfig(tmp, 22)
    var cfg = loadConfig(tmp)
    cfg.concurrency.maxAgents = 1
    writeScriptoriumConfig(tmp, cfg)

    var callOrder: seq[string] = @[]
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Emulate architect, manager, and coding agent by ticketId role markers.
      callOrder.add(request.ticketId)
      case request.ticketId
      of "run":
        writeFile(
          request.workingDir / "areas/01-full-flow.md",
          "# Area 01\n\n## Goal\n- Full flow.\n",
        )
        result = AgentRunResult(
          backend: harnessCodex,
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          lastMessage: "areas done",
          timeoutKind: "none",
        )
      of "manager-01-full-flow":
        recordSubmitTickets("01-full-flow", @["# Full Flow\n\n**Area:** 01-full-flow"])
        result = AgentRunResult(
          backend: harnessCodex,
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          lastMessage: "tickets submitted",
          timeoutKind: "none",
        )
      of "0001-prediction":
        result = AgentRunResult(
          backend: harnessCodex,
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          lastMessage: """{"predicted_difficulty": "easy", "predicted_duration_minutes": 10, "reasoning": "Simple ticket."}""",
          timeoutKind: "none",
        )
      of "0001":
        writeFile(request.workingDir / "flow-output.txt", "done\n")
        runCmdOrDie("git -C " & quoteShell(request.workingDir) & " add flow-output.txt")
        runCmdOrDie("git -C " & quoteShell(request.workingDir) & " commit -m test-v1-39-flow-output")
        callSubmitPrTool("ship flow")
        result = AgentRunResult(
          backend: harnessCodex,
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          lastMessage: "Done.",
          timeoutKind: "none",
        )
      else:
        raise newException(ValueError, "unexpected runner ticket id: " & request.ticketId)

    runOrchestratorForTicks(tmp, 1, fakeRunner)

    let files = planTreeFiles(tmp)
    check callOrder == @["run", "manager-01-full-flow", "0001-prediction", "0001"]
    check "areas/01-full-flow.md" in files
    check "tickets/done/0001-full-flow.md" in files
    check "tickets/open/0001-full-flow.md" notin files
    check "tickets/in-progress/0001-full-flow.md" notin files
    check "queue/merge/pending/0001-0001.md" notin files

    let (masterFile, masterRc) = execCmdEx("git -C " & quoteShell(tmp) & " show master:flow-output.txt")
    check masterRc == 0
    check masterFile.strip() == "done"

    validateTicketStateInvariant(tmp)
    validateTransitionCommitInvariant(tmp)

suite "orchestrator agent enqueue with fakes":
  setup:

    while consumeSubmitPrSummary() != "": discard
    tickSleepOverrideMs = 0

  teardown:
    tickSleepOverrideMs = -1

  test "orchestrator tick assigns and executes before merge queue processing":
    withTempRepo("scriptorium_test_tick_assign_execute_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      addPassingMakefile(repoPath)
      writeSpecInPlan(repoPath, "# Spec\n\nDrive orchestrator tick.\n")
      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
      addTicketToPlan(repoPath, "open", "0002-second.md", "# Ticket 2\n\n**Area:** b\n")

      let firstAssignment = assignOldestOpenTicket(repoPath)
      writeFile(firstAssignment.worktree / "ticket-output.txt", "done\n")
      runCmdOrDie("git -C " & quoteShell(firstAssignment.worktree) & " add ticket-output.txt")
      runCmdOrDie("git -C " & quoteShell(firstAssignment.worktree) & " commit -m ticket-output")
      discard enqueueMergeRequest(repoPath, firstAssignment, "first summary")

      proc fakeRunner(request: AgentRunRequest): AgentRunResult =
        ## Ticket 0002 returns without submit_pr so it gets reopened as stalled.
        if request.ticketId == "run":
          return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
        elif request.ticketId.startsWith("manager"):
          return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
        elif request.ticketId.endsWith("-prediction"):
          return AgentRunResult(exitCode: 1, attemptCount: 1, stdout: "")
        else:
          return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "", lastMessage: "ok", timeoutKind: "none")

      writeOrchestratorEndpointConfig(repoPath, 0)
      runOrchestratorForTicks(repoPath, 1, fakeRunner)

      let files = planTreeFiles(repoPath)
      check "tickets/done/0001-first.md" in files
      check "tickets/open/0002-second.md" in files
      check pendingQueueFiles(repoPath).len == 0

      let commits = latestPlanCommits(repoPath, 20)
      check commits.anyIt(it == "scriptorium: complete ticket 0001")
      check commits.anyIt(it == "scriptorium: review ticket 0001")
      check commits.anyIt(it.startsWith("scriptorium: reopen failed ticket"))
      check commits.anyIt(it == "scriptorium: record agent run 0002-second")
      check commits.anyIt(it == "scriptorium: assign ticket 0002-second")
    )

  test "end-to-end happy path from spec to done":
    withTempRepo("scriptorium_test_e2e_happy_path_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      addPassingMakefile(repoPath)

      var architectCalls = 0
      proc architectGenerator(model: string, spec: string): seq[AreaDocument] =
        ## Return one deterministic area document from spec input.
        inc architectCalls
        check model == "claude-opus-4-6"
        check "scriptorium plan" in spec
        result = @[
          AreaDocument(
            path: "01-e2e.md",
            content: "# Area 01\n\n## Goal\n- Validate V1 happy path.\n",
          )
        ]

      let syncedAreas = syncAreasFromSpec(repoPath, architectGenerator)
      check syncedAreas
      check architectCalls == 1

      addTicketToPlan(repoPath, "open", "0001-e2e-happy-path.md",
        "# Ticket 1\n\nImplement end-to-end flow.\n\n**Area:** 01-e2e\n")

      let filesAfterPlanning = planTreeFiles(repoPath)
      check "areas/01-e2e.md" in filesAfterPlanning
      check "tickets/open/0001-e2e-happy-path.md" in filesAfterPlanning

      let assignment = assignOldestOpenTicket(repoPath)
      check assignment.inProgressTicket == "tickets/in-progress/0001-e2e-happy-path.md"
      writeFile(assignment.worktree / "e2e-output.txt", "done\n")
      runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add e2e-output.txt")
      runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m test-e2e-ticket-output")
      let (ticketHead, ticketHeadRc) = execCmdEx("git -C " & quoteShell(assignment.worktree) & " rev-parse HEAD")
      doAssert ticketHeadRc == 0

      proc fakeRunner(request: AgentRunRequest): AgentRunResult =
        ## Return a deterministic successful output and request merge submission.
        discard request
        callSubmitPrTool("ship e2e")
        result = AgentRunResult(
          backend: harnessCodex,
          command: @["codex", "exec"],
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          stdout: "",
          logFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.jsonl",
          lastMessageFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.last_message.txt",
          lastMessage: "Done.",
          timeoutKind: "none",
        )

      discard executeAssignedTicket(repoPath, assignment, fakeRunner)
      let pending = pendingQueueFiles(repoPath)
      check pending.len == 1
      check pending[0] == "queue/merge/pending/0001-0001.md"

      let processed = processMergeQueue(repoPath, noopRunner)
      check processed
      check pendingQueueFiles(repoPath).len == 0

      let finalFiles = planTreeFiles(repoPath)
      check "tickets/done/0001-e2e-happy-path.md" in finalFiles
      check "tickets/open/0001-e2e-happy-path.md" notin finalFiles
      check "tickets/in-progress/0001-e2e-happy-path.md" notin finalFiles

      let (masterOutput, masterRc) = execCmdEx("git -C " & quoteShell(repoPath) & " show master:e2e-output.txt")
      check masterRc == 0
      check masterOutput.strip() == "done"

      let (_, ancestorRc) = execCmdEx(
        "git -C " & quoteShell(repoPath) & " merge-base --is-ancestor " & ticketHead.strip() & " master"
      )
      check ancestorRc == 0

      validateTicketStateInvariant(repoPath)
      validateTransitionCommitInvariant(repoPath)
    )

suite "non-blocking tick loop":
  setup:

    while consumeSubmitPrSummary() != "": discard
    discard consumeReviewDecision()
    tickSleepOverrideMs = 0

  teardown:
    tickSleepOverrideMs = -1

  test "serial mode executes one ticket per tick when maxAgents is 1":
    let tmp = getTempDir() / "scriptorium_test_serial_tick"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    writeSpecInPlan(tmp, "# Spec\n\nSerial test.\n")
    addTicketToPlan(tmp, "open", "0001-serial.md", "# Ticket 1\n\n**Area:** a\n")

    var codingCalled = false
    let fakeRunner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      if request.ticketId == "run":
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId.startsWith("manager"):
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId == "0001-prediction":
        return AgentRunResult(exitCode: 1, attemptCount: 1, stdout: "")
      elif request.ticketId == "0001":
        codingCalled = true
        recordSubmitPrSummary("serial done", "0001")
        return AgentRunResult(exitCode: 0, attemptCount: 1, lastMessage: "Done.", timeoutKind: "none")
      else:
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "", timeoutKind: "none")

    var cfg = defaultConfig()
    cfg.concurrency.maxAgents = 1
    writeScriptoriumConfig(tmp, cfg)

    runOrchestratorForTicks(tmp, 1, fakeRunner)

    check codingCalled
    let files = planTreeFiles(tmp)
    # Serial mode: ticket submitted and merged in the same tick.
    check "tickets/done/0001-serial.md" in files
    check "tickets/open/0001-serial.md" notin files

suite "concurrent agent execution":
  setup:

    while consumeSubmitPrSummary() != "": discard
    tickSleepOverrideMs = 0

  teardown:
    tickSleepOverrideMs = -1

  test "two agents run concurrently in separate worktrees without interfering":
    let tmp = getTempDir() / "scriptorium_test_concurrent_agents"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    writeSpecInPlan(tmp, "# Spec\n\nConcurrent test.\n")
    addTicketToPlan(tmp, "open", "0001-alpha.md", "# Ticket Alpha\n\n**Area:** area-a\n")
    addTicketToPlan(tmp, "open", "0002-beta.md", "# Ticket Beta\n\n**Area:** area-b\n")

    var cfg = defaultConfig()
    cfg.concurrency.maxAgents = 2
    writeScriptoriumConfig(tmp, cfg)

    var codingCallCount = 0
    var codingCallLock: Lock
    initLock(codingCallLock)
    var seenTickets: seq[string] = @[]

    let fakeRunner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      if request.ticketId == "run":
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId.startsWith("manager"):
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId.endsWith("-prediction"):
        return AgentRunResult(exitCode: 1, attemptCount: 1, stdout: "")
      elif request.ticketId == "0001" or request.ticketId == "0002":
        {.cast(gcsafe).}:
          acquire(codingCallLock)
          inc codingCallCount
          seenTickets.add(request.ticketId)
          release(codingCallLock)
        recordSubmitPrSummary("done " & request.ticketId, request.ticketId)
        return AgentRunResult(exitCode: 0, attemptCount: 1, lastMessage: "Done.", timeoutKind: "none")
      else:
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "", timeoutKind: "none")

    runOrchestratorForTicks(tmp, 3, fakeRunner)

    acquire(codingCallLock)
    let finalCount = codingCallCount
    let finalTickets = seenTickets
    release(codingCallLock)
    deinitLock(codingCallLock)

    check finalCount == 2
    check "0001" in finalTickets
    check "0002" in finalTickets

    let files = planTreeFiles(tmp)
    check "tickets/open/0001-alpha.md" notin files
    check "tickets/open/0002-beta.md" notin files

  test "submit_pr correctly identifies calling agent ticket in parallel mode":
    let tmp = getTempDir() / "scriptorium_test_concurrent_submit_pr"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** area-x\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** area-y\n")

    let assignment1 = assignOldestOpenTicket(tmp)
    let assignment2 = assignOldestOpenTicket(tmp)
    check assignment1.inProgressTicket.len > 0
    check assignment2.inProgressTicket.len > 0

    setActiveTicketWorktree(assignment1.worktree, "0001")
    setActiveTicketWorktree(assignment2.worktree, "0002")
    defer: clearActiveTicketWorktree()

    let httpServer = createOrchestratorServer()
    let submitPrHandler = httpServer.server.toolHandlers["submit_pr"]

    discard submitPrHandler(%*{"summary": "done ticket 1", "ticket_id": "0001"})
    discard submitPrHandler(%*{"summary": "done ticket 2", "ticket_id": "0002"})

    let summary1 = consumeSubmitPrSummary("0001")
    let summary2 = consumeSubmitPrSummary("0002")
    check summary1 == "done ticket 1"
    check summary2 == "done ticket 2"

  test "concurrent start: all open tickets fill available slots in one tick":
    let tmp = getTempDir() / "scriptorium_test_concurrent_start"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    writeSpecInPlan(tmp, "# Spec\n\nConcurrent start test.\n")
    addTicketToPlan(tmp, "open", "0001-alpha.md", "# Ticket Alpha\n\n**Area:** area-a\n")
    addTicketToPlan(tmp, "open", "0002-beta.md", "# Ticket Beta\n\n**Area:** area-b\n")
    addTicketToPlan(tmp, "open", "0003-gamma.md", "# Ticket Gamma\n\n**Area:** area-c\n")

    var cfg = defaultConfig()
    cfg.concurrency.maxAgents = 4
    writeScriptoriumConfig(tmp, cfg)

    var tickCounter = 0
    var tickCounterLock: Lock
    initLock(tickCounterLock)
    var codingStartTicks: Table[string, int] = initTable[string, int]()

    let fakeRunner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      ## Track which tick each coding agent starts on.
      if request.ticketId == "run":
        {.cast(gcsafe).}:
          acquire(tickCounterLock)
          inc tickCounter
          release(tickCounterLock)
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId.startsWith("manager"):
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId.endsWith("-prediction"):
        return AgentRunResult(exitCode: 1, attemptCount: 1, stdout: "")
      elif request.ticketId in ["0001", "0002", "0003"]:
        {.cast(gcsafe).}:
          acquire(tickCounterLock)
          codingStartTicks[request.ticketId] = tickCounter
          release(tickCounterLock)
        recordSubmitPrSummary("done " & request.ticketId, request.ticketId)
        return AgentRunResult(exitCode: 0, attemptCount: 1, lastMessage: "Done.", timeoutKind: "none")
      else:
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "", timeoutKind: "none")

    runOrchestratorForTicks(tmp, 3, fakeRunner)

    acquire(tickCounterLock)
    let finalTicks = codingStartTicks
    release(tickCounterLock)
    deinitLock(tickCounterLock)

    # All 3 tickets must have been started.
    check finalTicks.len == 3
    check "0001" in finalTicks
    check "0002" in finalTicks
    check "0003" in finalTicks

    # All 3 coding agents should start on the same tick (fill available slots).
    var tickValues: seq[int] = @[]
    for ticketId, tick in finalTicks:
      tickValues.add(tick)
    check tickValues.deduplicate().len == 1

  test "managers are prioritized over coding agents when slots are scarce":
    let tmp = getTempDir() / "scriptorium_test_manager_priority"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    writeSpecInPlan(tmp, "# Spec\n\nManager priority test.\n")
    addAreaToPlan(tmp, "area-a.md", "# Area A\n")
    addAreaToPlan(tmp, "area-b.md", "# Area B\n")
    addTicketToPlan(tmp, "open", "0001-task.md", "# Task\n\n**Area:** area-a\n")

    var cfg = defaultConfig()
    cfg.concurrency.maxAgents = 2
    writeScriptoriumConfig(tmp, cfg)

    var callOrder: seq[string] = @[]
    var callOrderLock: Lock
    initLock(callOrderLock)

    let fakeRunner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      ## Track invocation order by ticketId.
      if request.ticketId == "run":
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId.startsWith("manager"):
        {.cast(gcsafe).}:
          acquire(callOrderLock)
          callOrder.add(request.ticketId)
          release(callOrderLock)
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId.endsWith("-prediction"):
        return AgentRunResult(exitCode: 1, attemptCount: 1, stdout: "")
      elif request.ticketId == "0001":
        {.cast(gcsafe).}:
          acquire(callOrderLock)
          callOrder.add(request.ticketId)
          release(callOrderLock)
        recordSubmitPrSummary("done 0001", "0001")
        return AgentRunResult(exitCode: 0, attemptCount: 1, lastMessage: "Done.", timeoutKind: "none")
      else:
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "", timeoutKind: "none")

    runOrchestratorForTicks(tmp, 4, fakeRunner)

    acquire(callOrderLock)
    let finalOrder = callOrder
    release(callOrderLock)
    deinitLock(callOrderLock)

    # Manager for area-b must appear before the coding agent for ticket 0001.
    let managerIdx = finalOrder.find("manager-area-b")
    let coderIdx = finalOrder.find("0001")
    check managerIdx >= 0
    check coderIdx >= 0
    check managerIdx < coderIdx

  test "stall detection works independently per agent":
    let tmp = getTempDir() / "scriptorium_test_concurrent_stall"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-staller.md", "# Ticket Staller\n\n**Area:** area-s\n")
    addTicketToPlan(tmp, "open", "0002-submitter.md", "# Ticket Submitter\n\n**Area:** area-t\n")
    var stallCfg = defaultConfig()
    stallCfg.timeouts.codingAgentMaxAttempts = 2
    writeScriptoriumConfig(tmp, stallCfg)

    let assignment1 = assignOldestOpenTicket(tmp)
    let assignment2 = assignOldestOpenTicket(tmp)
    check assignment1.inProgressTicket.len > 0
    check assignment2.inProgressTicket.len > 0

    ticketStartTimes["0001"] = epochTime()
    ticketStartTimes["0002"] = epochTime()
    ticketAttemptCounts["0001"] = 0
    ticketAttemptCounts["0002"] = 0
    ticketCodingWalls["0001"] = 0.0
    ticketCodingWalls["0002"] = 0.0
    ticketTestWalls["0001"] = 0.0
    ticketTestWalls["0002"] = 0.0
    ticketModels["0001"] = ""
    ticketModels["0002"] = ""
    ticketStdoutBytes["0001"] = 0
    ticketStdoutBytes["0002"] = 0

    var stallCallCount = 0
    proc stallingRunner(request: AgentRunRequest): AgentRunResult =
      ## Stalls on every call: exit 0 without calling submit_pr.
      inc stallCallCount
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        lastMessage: "I stalled.",
        timeoutKind: "none",
      )

    proc submittingRunner(request: AgentRunRequest): AgentRunResult =
      ## Submits immediately on first call.
      recordSubmitPrSummary("submitted", "0002")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        lastMessage: "Done.",
        timeoutKind: "none",
      )

    let result1 = executeAssignedTicket(tmp, assignment1, stallingRunner)
    let result2 = executeAssignedTicket(tmp, assignment2, submittingRunner)

    check stallCallCount == 2
    check result1.submitted == false
    check result2.submitted == true

    let files = planTreeFiles(tmp)
    check "tickets/open/0001-staller.md" in files
    let hasMergeEntry = files.anyIt(it.startsWith("queue/merge/pending/") and it.contains("0002"))
    check hasMergeEntry

suite "agent pool thread lifecycle":
  setup:
    ensurePoolResultChanOpen()
    # Drain any leftover state from prior tests.
    joinAllAgentThreads()

  teardown:
    joinAllAgentThreads()

  test "start 2 coding agents, verify counts, collect completions":
    proc coderWorker(args: AgentThreadArgs) {.thread.} =
      ## Sleep briefly then send a completion result back to the pool.
      sleep(50)
      sendPoolResult(AgentPoolCompletionResult(
        role: arCoder,
        ticketId: args.ticketId,
        result: AgentRunResult(exitCode: 0, submitted: true),
      ))

    let assignment1 = TicketAssignment(
      inProgressTicket: "tickets/in-progress/0001-alpha.md",
      branch: "scriptorium/ticket-0001",
      worktree: "/tmp/fake-wt-0001",
    )
    let assignment2 = TicketAssignment(
      inProgressTicket: "tickets/in-progress/0002-beta.md",
      branch: "scriptorium/ticket-0002",
      worktree: "/tmp/fake-wt-0002",
    )

    startCodingAgentAsync("/tmp", assignment1, 4, coderWorker)
    startCodingAgentAsync("/tmp", assignment2, 4, coderWorker)

    check runningAgentCount() == 2
    check runningAgentCountByRole(arCoder) == 2
    check emptySlotCount(4) == 2

    # Wait for threads to finish and send results.
    sleep(200)

    let completions = checkCompletedAgents()
    check completions.len == 2
    check runningAgentCount() == 0

    var completedIds: seq[string] = @[]
    for c in completions:
      check c.role == arCoder
      check c.result.exitCode == 0
      check c.result.submitted == true
      completedIds.add(c.ticketId)
    completedIds.sort()
    check completedIds == @["0001", "0002"]

  test "mixed manager and coder share the slot pool correctly":
    proc mixedWorker(args: AgentThreadArgs) {.thread.} =
      ## Sleep briefly then send a completion tagged by the args role marker.
      sleep(50)
      if args.areaId.len > 0:
        sendPoolResult(AgentPoolCompletionResult(
          role: arManager,
          areaId: args.areaId,
          result: AgentRunResult(exitCode: 0),
        ))
      else:
        sendPoolResult(AgentPoolCompletionResult(
          role: arCoder,
          ticketId: args.ticketId,
          result: AgentRunResult(exitCode: 0, submitted: true),
        ))

    let coderAssignment = TicketAssignment(
      inProgressTicket: "tickets/in-progress/0003-gamma.md",
      branch: "scriptorium/ticket-0003",
      worktree: "/tmp/fake-wt-0003",
    )

    startManagerAgentAsync("/tmp", "backend-api", "# Area\n", "/tmp/plan", 100, 4, mixedWorker)
    startCodingAgentAsync("/tmp", coderAssignment, 4, mixedWorker)

    check runningAgentCount() == 2
    check runningAgentCountByRole(arManager) == 1
    check runningAgentCountByRole(arCoder) == 1
    check emptySlotCount(4) == 2

    sleep(200)

    let completions = checkCompletedAgents()
    check completions.len == 2
    check runningAgentCount() == 0
    check emptySlotCount(4) == 4

    var hasManager = false
    var hasCoder = false
    for c in completions:
      if c.role == arManager:
        check c.areaId == "backend-api"
        hasManager = true
      elif c.role == arCoder:
        check c.ticketId == "0003"
        check c.result.submitted == true
        hasCoder = true
    check hasManager
    check hasCoder

suite "concurrent manager completion ticket ID serialization":
  setup:

    while consumeSubmitPrSummary() != "": discard
    tickSleepOverrideMs = 0

  teardown:
    tickSleepOverrideMs = -1

  test "two managers completing concurrently produce non-overlapping ticket IDs":
    let tmp = getTempDir() / "scriptorium_test_concurrent_manager_ids"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    writeSpecInPlan(tmp, "# Spec\n\nConcurrent manager ID test.\n")
    addAreaToPlan(tmp, "area-a.md", "# Area A\n\n## Goal\n- Area A work.\n")
    addAreaToPlan(tmp, "area-b.md", "# Area B\n\n## Goal\n- Area B work.\n")

    var cfg = defaultConfig()
    cfg.concurrency.maxAgents = 2
    writeScriptoriumConfig(tmp, cfg)

    let fakeRunner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      ## Architect no-ops; managers submit 2 tickets each via recordSubmitTickets.
      if request.ticketId == "run":
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId == "manager-area-a":
        recordSubmitTickets("area-a", @[
          "# Task A1\n\n**Area:** area-a",
          "# Task A2\n\n**Area:** area-a",
        ])
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId == "manager-area-b":
        recordSubmitTickets("area-b", @[
          "# Task B1\n\n**Area:** area-b",
          "# Task B2\n\n**Area:** area-b",
        ])
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId.endsWith("-prediction"):
        return AgentRunResult(exitCode: 1, attemptCount: 1, stdout: "")
      else:
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "", timeoutKind: "none")

    runOrchestratorForTicks(tmp, 3, fakeRunner)

    # Collect ticket files from tickets/open/ on the plan branch.
    let allFiles = planTreeFiles(tmp)
    let openTickets = allFiles.filterIt(it.startsWith("tickets/open/") and it.endsWith(".md"))

    check openTickets.len == 4

    # Extract numeric prefixes and verify uniqueness and monotonic ordering.
    var prefixes: seq[int] = @[]
    for ticketFile in openTickets:
      let fileName = ticketFile.split("/")[^1]
      let dashIdx = fileName.find('-')
      let numStr = fileName[0..<dashIdx]
      prefixes.add(parseInt(numStr))
    prefixes.sort()

    # All IDs must be unique.
    check prefixes.deduplicate() == prefixes

    # IDs must be monotonically increasing.
    for i in 1..<prefixes.len:
      check prefixes[i] > prefixes[i - 1]

    # Verify each ticket's area field matches the correct area.
    var areaACounts = 0
    var areaBCounts = 0
    for ticketFile in openTickets:
      let content = readPlanFile(tmp, ticketFile)
      let areaId = parseAreaFromTicketContent(content)
      if areaId == "area-a":
        inc areaACounts
      elif areaId == "area-b":
        inc areaBCounts
    check areaACounts == 2
    check areaBCounts == 2
