## Tests for orchestrator planning: spec updates, invariants, bootstrap.

import
  std/[algorithm, json, locks, os, osproc, sequtils, sha1, strformat, strutils, tables, tempfiles, times, unittest],
  jsony,
  scriptorium/[agent_runner, config, init, logging, orchestrator, ticket_metadata],
  helpers

suite "orchestrator plan spec update":
  test "updateSpecFromArchitect runs in plan worktree, reads repo path, and commits":
    let tmp = getTempDir() / "scriptorium_test_plan_update_spec"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    writeFile(tmp / "source-marker.txt", "alpha\n")
    runCmdOrDie("git -C " & quoteShell(tmp) & " add source-marker.txt")
    runCmdOrDie("git -C " & quoteShell(tmp) & " commit -m test-add-source-marker")
    var writtenCfg = defaultConfig()
    writtenCfg.agents.architect.reasoningEffort = "high"
    writeScriptoriumConfig(tmp, writtenCfg)

    var callCount = 0
    var capturedFirstModel = ""
    var capturedFirstReasoningEffort = ""
    var capturedFirstWorkingDir = ""
    var capturedFirstRepoPath = ""
    var capturedFirstSpec = ""
    var capturedFirstUserRequest = ""
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Read source via repo path from prompt and update spec.md in plan worktree.
      inc callCount
      check req.heartbeatIntervalMs == 0
      check req.onEvent.isNil
      let repoPathMarker = "Project repository root path (read project source files and instructions from here):\n"
      let repoPathMarkerIndex = req.prompt.find(repoPathMarker)
      doAssert repoPathMarkerIndex >= 0
      let repoPathStart = repoPathMarkerIndex + repoPathMarker.len
      let repoPathEnd = req.prompt.find('\n', repoPathStart)
      doAssert repoPathEnd > repoPathStart
      let repoPathFromPrompt = req.prompt[repoPathStart..<repoPathEnd].strip()
      let priorSpec = readFile(req.workingDir / "spec.md")
      let sourceMarker = readFile(repoPathFromPrompt / "source-marker.txt").strip()
      writeFile(req.workingDir / "spec.md", "# Revised Spec\n\n- marker: " & sourceMarker & "\n")

      if callCount == 1:
        capturedFirstModel = req.model
        capturedFirstReasoningEffort = req.reasoningEffort
        capturedFirstWorkingDir = req.workingDir
        capturedFirstRepoPath = repoPathFromPrompt
        capturedFirstSpec = priorSpec
        capturedFirstUserRequest = req.prompt

      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "Updated spec.",
        timeoutKind: "none",
      )

    let before = planCommitCount(tmp)
    let changed = updateSpecFromArchitect(tmp, "expand scope", fakeRunner)
    let after = planCommitCount(tmp)
    let unchanged = updateSpecFromArchitect(tmp, "expand scope", fakeRunner)
    let afterUnchanged = planCommitCount(tmp)
    let (specBody, specRc) = execCmdEx("git -C " & quoteShell(tmp) & " show scriptorium/plan:spec.md")
    let (logOutput, logRc) = execCmdEx("git -C " & quoteShell(tmp) & " log --oneline -1 scriptorium/plan")

    check changed
    check not unchanged
    check callCount == 2
    check capturedFirstModel == "claude-opus-4-6"
    check capturedFirstReasoningEffort == "high"
    check capturedFirstWorkingDir != tmp
    check capturedFirstRepoPath == tmp
    check "scriptorium plan" in capturedFirstSpec
    check "expand scope" in capturedFirstUserRequest
    check "AGENTS.md" in capturedFirstUserRequest
    check "Active working directory path (this is the scriptorium plan worktree):" in capturedFirstUserRequest
    check "Only edit spec.md in this working directory." in capturedFirstUserRequest
    check "Treat `" in capturedFirstUserRequest
    check "as the authoritative planning file." in capturedFirstUserRequest
    check "If the request is discussion, analysis, or questions, reply directly and do not edit spec.md." in capturedFirstUserRequest
    check "Only edit spec.md when the engineer is asking to change plan content." in capturedFirstUserRequest
    check "Inline convenience copy of `spec.md` from the plan worktree:" in capturedFirstUserRequest
    check after == before + 1
    check afterUnchanged == after
    check specRc == 0
    check specBody == "# Revised Spec\n\n- marker: alpha\n"
    check logRc == 0
    check "scriptorium: update spec from architect" in logOutput

  test "updateSpecFromArchitect rejects writes outside spec.md":
    let tmp = getTempDir() / "scriptorium_test_plan_out_of_scope"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Write to spec.md and one out-of-scope path to trigger guard failure.
      writeFile(req.workingDir / "spec.md", "# Updated Spec\n")
      writeFile(req.workingDir / "areas/01-out-of-scope.md", "# Bad write\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "done",
        timeoutKind: "none",
      )

    let before = planCommitCount(tmp)
    expect ValueError:
      discard updateSpecFromArchitect(tmp, "expand scope", fakeRunner)
    let after = planCommitCount(tmp)
    let files = planTreeFiles(tmp)

    check after == before
    check "areas/01-out-of-scope.md" notin files

  test "updateSpecFromArchitect recovers stale managed deterministic worktree conflicts":
    let tmp = getTempDir() / "scriptorium_test_plan_stale_temp_conflict"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    var managedPlanPath = ""
    proc bootstrapRunner(req: AgentRunRequest): AgentRunResult =
      ## Capture the deterministic managed plan worktree path.
      managedPlanPath = req.workingDir
      writeFile(req.workingDir / "spec.md", "# Updated Spec\n\n- bootstrap\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "done",
        timeoutKind: "none",
      )
    discard updateSpecFromArchitect(tmp, "bootstrap managed path", bootstrapRunner)
    check managedPlanPath.len > 0
    check "/worktrees/plan" in normalizedPathForTest(managedPlanPath)

    # Simulate Docker crash: worktree directory is gone but .git/worktrees/plan
    # metadata remains, causing a stale conflict on next access.
    removeDir(managedPlanPath)

    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Update spec.md in the recovered deterministic worktree.
      writeFile(req.workingDir / "spec.md", "# Updated Spec\n\n- recovered\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "done",
        timeoutKind: "none",
      )

    let changed = updateSpecFromArchitect(tmp, "recover stale temp", fakeRunner)
    let worktrees = gitWorktreePaths(tmp)

    check changed
    # Plan worktree persists after the operation (persistent worktree pattern).
    check managedPlanPath in worktrees

  test "updateSpecFromArchitect keeps non-managed plan worktree conflicts intact":
    let tmp = getTempDir() / "scriptorium_test_plan_manual_conflict"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    let manualPath = getTempDir() / "scriptorium_manual_plan_conflict"
    if dirExists(manualPath):
      removeDir(manualPath)
    runCmdOrDie("git -C " & quoteShell(tmp) & " worktree add " & quoteShell(manualPath) & " scriptorium/plan")
    defer:
      discard execCmdEx("git -C " & quoteShell(tmp) & " worktree remove --force " & quoteShell(manualPath))
      discard execCmdEx("git -C " & quoteShell(tmp) & " worktree prune")
      if dirExists(manualPath):
        removeDir(manualPath)

    var runnerCalls = 0
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Track invocations; this runner should not be called on add conflict.
      inc runnerCalls
      discard req
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "",
        timeoutKind: "none",
      )

    var errorMessage = ""
    try:
      discard updateSpecFromArchitect(tmp, "conflict", fakeRunner)
    except IOError as err:
      errorMessage = err.msg

    let worktrees = gitWorktreePaths(tmp)
    check runnerCalls == 0
    check "already used by worktree" in errorMessage
    check manualPath in worktrees

  test "stale worktree metadata is pruned before creating plan worktree":
    let tmp = getTempDir() / "scriptorium_test_stale_prune"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    # First call captures the managed plan path.
    var managedPlanPath = ""
    proc bootstrapRunner(req: AgentRunRequest): AgentRunResult =
      ## Capture the deterministic managed plan worktree path.
      managedPlanPath = req.workingDir
      writeFile(req.workingDir / "spec.md", "# Spec\n\n- bootstrap\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "done",
        timeoutKind: "none",
      )
    discard updateSpecFromArchitect(tmp, "bootstrap", bootstrapRunner)
    check managedPlanPath.len > 0

    # Simulate Docker scenario: worktree checkout dir is gone but
    # .git/worktrees/plan metadata persists, causing a stale conflict.
    removeDir(managedPlanPath)

    proc recoveryRunner(req: AgentRunRequest): AgentRunResult =
      ## Verify the worktree was created successfully after prune.
      writeFile(req.workingDir / "spec.md", "# Spec\n\n- recovered after prune\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "done",
        timeoutKind: "none",
      )

    let changed = updateSpecFromArchitect(tmp, "recover after prune", recoveryRunner)
    check changed
    # Plan worktree persists after the operation (persistent worktree pattern).
    let worktrees = gitWorktreePaths(tmp)
    check managedPlanPath in worktrees

  test "updateSpecFromArchitect fails fast when planner lock is held":
    let tmp = getTempDir() / "scriptorium_test_plan_lock_busy"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    var managedPlanPath = ""
    proc bootstrapRunner(req: AgentRunRequest): AgentRunResult =
      ## Capture deterministic plan path so tests can derive lock location.
      managedPlanPath = req.workingDir
      writeFile(req.workingDir / "spec.md", "# Updated Spec\n\n- bootstrap\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "done",
        timeoutKind: "none",
      )
    discard updateSpecFromArchitect(tmp, "bootstrap lock path", bootstrapRunner)
    check managedPlanPath.len > 0

    let managedRepoRoot = parentDir(parentDir(managedPlanPath))
    let lockPath = managedRepoRoot / "locks/repo.lock"
    createDir(parentDir(lockPath))
    createDir(lockPath)
    let pidPath = lockPath / "pid"
    # Use PID 1 (init/systemd) — always alive, never us. Cannot use our own PID
    # because lockPathIsStale treats same-PID locks as stale (cross-container fix).
    writeFile(pidPath, "1\n")
    defer:
      if fileExists(pidPath):
        removeFile(pidPath)
      if dirExists(lockPath):
        removeDir(lockPath)

    var runnerCalls = 0
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Track invocations; lock contention should fail before runner starts.
      inc runnerCalls
      discard req
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "",
        timeoutKind: "none",
      )

    var errorMessage = ""
    try:
      discard updateSpecFromArchitect(tmp, "blocked by lock", fakeRunner)
    except IOError as err:
      errorMessage = err.msg

    check runnerCalls == 0
    check "another planner/manager is active" in errorMessage

suite "orchestrator invariants":
  test "ticket state invariant fails when same ticket exists in multiple state directories":
    let tmp = getTempDir() / "scriptorium_test_invariant_duplicate_ticket_states"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
    addTicketToPlan(tmp, "done", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    expect ValueError:
      validateTicketStateInvariant(tmp)

  test "transition commit invariant passes for orchestrator-managed state moves":
    let tmp = getTempDir() / "scriptorium_test_invariant_transition_pass"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    discard assignOldestOpenTicket(tmp)
    validateTransitionCommitInvariant(tmp)

  test "transition commit invariant fails for non-orchestrator ticket move commit":
    let tmp = getTempDir() / "scriptorium_test_invariant_transition_fail"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
    moveTicketStateInPlan(tmp, "open", "in-progress", "0001-first.md")

    expect ValueError:
      validateTransitionCommitInvariant(tmp)

  test "simulated crash during ticket move keeps prior valid state":
    let tmp = getTempDir() / "scriptorium_test_invariant_no_partial_move_on_crash"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
    let before = planCommitCount(tmp)

    expect IOError:
      withPlanWorktree(tmp, "simulated_crash_partial_move", proc(planPath: string) =
        moveFile(
          planPath / "tickets/open/0001-first.md",
          planPath / "tickets/in-progress/0001-first.md",
        )
        raise newException(IOError, "simulated crash before commit")
      )

    let files = planTreeFiles(tmp)
    let after = planCommitCount(tmp)
    check "tickets/open/0001-first.md" in files
    check "tickets/in-progress/0001-first.md" notin files
    check after == before
    validateTicketStateInvariant(tmp)

suite "orchestrator planning bootstrap":
  test "loads spec from plan branch":
    let tmp = getTempDir() / "scriptorium_test_plan_load_spec"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    let spec = loadSpecFromPlan(tmp)
    check "scriptorium plan" in spec

  test "missing spec raises error":
    let tmp = getTempDir() / "scriptorium_test_plan_missing_spec"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    removeSpecFromPlan(tmp)

    expect ValueError:
      discard loadSpecFromPlan(tmp)

  test "areas missing is true for blank plan and false when area exists":
    let tmp = getTempDir() / "scriptorium_test_areas_missing"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    check areasMissing(tmp)
    addAreaToPlan(tmp, "01-cli.md", "# Area 01\n")
    check not areasMissing(tmp)

  test "sync areas calls architect with configured model and spec":
    let tmp = getTempDir() / "scriptorium_test_sync_areas_call"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    var writtenCfg = defaultConfig()
    writtenCfg.agents.architect = AgentConfig(harness: harnessClaudeCode, model: "claude-opus-4-6")
    writeScriptoriumConfig(tmp, writtenCfg)

    var callCount = 0
    var capturedModel = ""
    var capturedSpec = ""
    proc generator(model: string, spec: string): seq[AreaDocument] =
      ## Capture architect invocation arguments and return one area.
      inc callCount
      capturedModel = model
      capturedSpec = spec
      result = @[
        AreaDocument(path: "01-cli.md", content: "# Area 01\n\n## Scope\n- CLI\n")
      ]

    let synced = syncAreasFromSpec(tmp, generator)
    check synced
    check callCount == 1
    check capturedModel == "claude-opus-4-6"
    check "scriptorium plan" in capturedSpec

    let (files, rc) = execCmdEx("git -C " & quoteShell(tmp) & " ls-tree -r --name-only scriptorium/plan")
    check rc == 0
    check "areas/01-cli.md" in files

  test "sync areas is idempotent on second run":
    let tmp = getTempDir() / "scriptorium_test_sync_areas_idempotent"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    var callCount = 0
    proc generator(model: string, spec: string): seq[AreaDocument] =
      ## Return stable area output for idempotence checks.
      inc callCount
      discard model
      discard spec
      result = @[
        AreaDocument(path: "01-cli.md", content: "# Area 01\n\n## Scope\n- CLI\n")
      ]

    let before = planCommitCount(tmp)
    let firstSync = syncAreasFromSpec(tmp, generator)
    let afterFirst = planCommitCount(tmp)
    let secondSync = syncAreasFromSpec(tmp, generator)
    let afterSecond = planCommitCount(tmp)

    check firstSync
    check not secondSync
    check callCount == 1
    check afterFirst == before + 2  # areas commit + spec hash marker commit
    check afterSecond == afterFirst

suite "orchestrator manager ticket bootstrap":
  test "areas needing tickets excludes areas with open or in-progress work":
    let tmp = getTempDir() / "scriptorium_test_areas_needing_tickets"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addAreaToPlan(tmp, "01-cli.md", "# Area 01\n")
    addAreaToPlan(tmp, "02-core.md", "# Area 02\n")
    addTicketToPlan(tmp, "open", "0001-cli-ticket.md", "# Ticket\n\n**Area:** 01-cli\n")

    let needed = areasNeedingTickets(tmp)
    check "areas/02-core.md" in needed
    check "areas/01-cli.md" notin needed

suite "orchestrator architect areas":
  test "runArchitectAreas commits files written by mocked architect runner":
    let tmp = getTempDir() / "scriptorium_test_v1_37_run_architect_areas"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    writeSpecInPlan(tmp, "# Spec\n\nBuild area files.\n")
    var writtenCfg = defaultConfig()
    writtenCfg.agents.architect.reasoningEffort = "high"
    writeScriptoriumConfig(tmp, writtenCfg)

    var callCount = 0
    var capturedRequest = AgentRunRequest()
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Write one area file directly into areas/ from the plan worktree.
      inc callCount
      capturedRequest = request
      writeFile(request.workingDir / "areas/01-arch.md", "# Area 01\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "areas written",
        timeoutKind: "none",
      )

    let before = planCommitCount(tmp)
    let changed = runArchitectAreas(tmp, fakeRunner)
    let after = planCommitCount(tmp)
    let files = planTreeFiles(tmp)

    check changed
    check callCount == 1
    check capturedRequest.ticketId == "run"
    check capturedRequest.model == resolveModel("claude-opus-4-6")
    check capturedRequest.reasoningEffort == "high"
    check capturedRequest.logRoot == tmp / ".scriptorium" / "logs" / "architect" / "areas"
    check tmp in capturedRequest.prompt
    check "AGENTS.md" in capturedRequest.prompt
    check "Active working directory path (this is the scriptorium plan worktree):" in capturedRequest.prompt
    check "Read `spec.md` in this working directory and write/update area markdown files directly under `areas/` in this working directory." in capturedRequest.prompt
    check "areas/01-arch.md" in files
    check after == before + 2  # areas commit + spec hash marker commit

  test "done tickets suppress areas from areasNeedingTickets":
    let tmp = getTempDir() / "scriptorium_test_done_ticket_suppression"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addAreaToPlan(tmp, "01-done-area.md", "# Area 01\n")
    addAreaToPlan(tmp, "02-pending-area.md", "# Area 02\n")
    addTicketToPlan(tmp, "done", "0001-done-area-summary.md", "# Done\n\n**Area:** 01-done-area\n")

    let needed = areasNeedingTickets(tmp)
    check "areas/02-pending-area.md" in needed
    check "areas/01-done-area.md" notin needed

  test "done ticket with unchanged area hash suppresses area":
    let tmp = getTempDir() / "scriptorium_test_done_unchanged_hash"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addAreaToPlan(tmp, "01-done-area.md", "# Area 01\n")
    addAreaToPlan(tmp, "02-pending-area.md", "# Area 02\n")
    addTicketToPlan(tmp, "done", "0001-done-area-summary.md", "# Done\n\n**Area:** 01-done-area\n")
    # Write area hashes matching current content
    var hashes = initTable[string, string]()
    hashes["01-done-area"] = $secureHash("# Area 01\n")
    hashes["02-pending-area"] = $secureHash("# Area 02\n")
    writeAreaHashesInPlan(tmp, hashes)

    let needed = areasNeedingTickets(tmp)
    check needed.len == 0  # both areas have matching hashes, done area not re-triggered

  test "done ticket with changed area content triggers new tickets":
    let tmp = getTempDir() / "scriptorium_test_done_changed_hash"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addAreaToPlan(tmp, "01-done-area.md", "# Area 01 v2\n")  # content differs from stored hash
    addAreaToPlan(tmp, "02-unchanged.md", "# Area 02\n")
    addTicketToPlan(tmp, "done", "0001-done-area-summary.md", "# Done\n\n**Area:** 01-done-area\n")
    # Write area hashes with old content hash for 01-done-area
    var hashes = initTable[string, string]()
    hashes["01-done-area"] = $secureHash("# Area 01 v1\n")  # old hash
    hashes["02-unchanged"] = $secureHash("# Area 02\n")  # matching hash
    writeAreaHashesInPlan(tmp, hashes)

    let needed = areasNeedingTickets(tmp)
    check "areas/01-done-area.md" in needed  # changed content triggers new tickets
    check "areas/02-unchanged.md" notin needed  # unchanged is suppressed

  test "open ticket blocks area even when content changed":
    let tmp = getTempDir() / "scriptorium_test_open_blocks_changed"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addAreaToPlan(tmp, "01-active.md", "# Area 01 v2\n")
    addTicketToPlan(tmp, "open", "0001-active-ticket.md", "# Ticket\n\n**Area:** 01-active\n")
    var hashes = initTable[string, string]()
    hashes["01-active"] = $secureHash("# Area 01 v1\n")  # old hash, content changed
    writeAreaHashesInPlan(tmp, hashes)

    let needed = areasNeedingTickets(tmp)
    check "areas/01-active.md" notin needed  # open ticket blocks regardless of content change

  test "architect creates spec hash marker on first run":
    let tmp = getTempDir() / "scriptorium_test_arch_spec_hash_first_run"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    writeSpecInPlan(tmp, "# Spec\n\nBuild a CLI tool.\n")

    proc generator(model: string, spec: string): seq[AreaDocument] =
      result = @[AreaDocument(path: "01-cli.md", content: "# CLI Area\n")]

    let synced = syncAreasFromSpec(tmp, generator)
    check synced

    let files = planTreeFiles(tmp)
    check "areas/.spec-hash" in files
    let hashContent = readPlanFile(tmp, "areas/.spec-hash").strip()
    check hashContent == $secureHash("# Spec\n\nBuild a CLI tool.\n")

  test "architect skips when spec unchanged":
    let tmp = getTempDir() / "scriptorium_test_arch_skip_unchanged"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    let specContent = "# Spec\n\nBuild a CLI tool.\n"
    writeSpecInPlan(tmp, specContent)
    addAreaToPlan(tmp, "01-cli.md", "# CLI Area\n")
    writeSpecHashInPlan(tmp, $secureHash(specContent))

    var callCount = 0
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      inc callCount
      result = AgentRunResult(backend: harnessClaudeCode, exitCode: 0, attempt: 1, attemptCount: 1)

    let changed = runArchitectAreas(tmp, fakeRunner)
    check not changed
    check callCount == 0  # architect was not invoked

  test "architect re-runs when spec changes":
    let tmp = getTempDir() / "scriptorium_test_arch_rerun_spec_changed"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    let oldSpec = "# Spec\n\nBuild a CLI tool.\n"
    writeSpecInPlan(tmp, "# Spec\n\nBuild a CLI tool with logging.\n")  # new content
    addAreaToPlan(tmp, "01-cli.md", "# CLI Area\n")
    writeSpecHashInPlan(tmp, $secureHash(oldSpec))  # hash of old spec

    var callCount = 0
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      inc callCount
      # Simulate architect writing an updated area
      writeFile(request.workingDir / "areas/02-logging.md", "# Logging Area\n")
      result = AgentRunResult(backend: harnessClaudeCode, exitCode: 0, attempt: 1, attemptCount: 1)

    let changed = runArchitectAreas(tmp, fakeRunner)
    check changed
    check callCount == 1

    let files = planTreeFiles(tmp)
    check "areas/02-logging.md" in files
    check "areas/.spec-hash" in files

  test "migration writes spec hash marker for existing areas without re-running":
    let tmp = getTempDir() / "scriptorium_test_arch_migration"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    let specContent = "# Spec\n\nExisting project.\n"
    writeSpecInPlan(tmp, specContent)
    addAreaToPlan(tmp, "01-cli.md", "# CLI Area\n")
    # No .spec-hash file — simulates pre-upgrade state

    var callCount = 0
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      inc callCount
      result = AgentRunResult(backend: harnessClaudeCode, exitCode: 0, attempt: 1, attemptCount: 1)

    let changed = runArchitectAreas(tmp, fakeRunner)
    check not changed  # migration only, no architect run
    check callCount == 0

    let files = planTreeFiles(tmp)
    check "areas/.spec-hash" in files  # marker was written
    let hashContent = readPlanFile(tmp, "areas/.spec-hash").strip()
    check hashContent == $secureHash(specContent)

suite "orchestrator one-shot plan runner":
  test "one-shot plan runner reads repo path context and commits spec only":
    withTempRepo("scriptorium_test_oneshot_plan_runner_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      writeFile(repoPath / "source-marker.txt", "integration-marker\n")
      runCmdOrDie("git -C " & quoteShell(repoPath) & " add source-marker.txt")
      runCmdOrDie("git -C " & quoteShell(repoPath) & " commit -m test-add-source-marker")

      var callCount = 0
      var capturedPrompt = ""
      var capturedRepoPath = ""
      proc fakeRunner(request: AgentRunRequest): AgentRunResult =
        ## Read the repo path from prompt context and update spec.md in plan worktree.
        inc callCount
        capturedPrompt = request.prompt
        let repoPathMarker = "Project repository root path (read project source files and instructions from here):\n"
        let markerIndex = request.prompt.find(repoPathMarker)
        doAssert markerIndex >= 0
        let pathStart = markerIndex + repoPathMarker.len
        let pathEnd = request.prompt.find('\n', pathStart)
        doAssert pathEnd > pathStart
        let repoPathFromPrompt = request.prompt[pathStart..<pathEnd].strip()
        capturedRepoPath = repoPathFromPrompt
        let marker = readFile(repoPathFromPrompt / "source-marker.txt").strip()
        writeFile(request.workingDir / "spec.md", "# Integration Spec\n\n- marker: " & marker & "\n")

        result = AgentRunResult(
          backend: harnessCodex,
          command: @["codex", "exec"],
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          stdout: "",
          logFile: request.workingDir / ".scriptorium/logs/architect/spec/attempt-01.jsonl",
          lastMessageFile: request.workingDir / ".scriptorium/logs/architect/spec/attempt-01.last_message.txt",
          lastMessage: "Updated spec",
          timeoutKind: "none",
        )

      let changed = updateSpecFromArchitect(repoPath, "sync source marker", fakeRunner)

      check changed
      check callCount == 1
      check capturedRepoPath == repoPath
      check "AGENTS.md" in capturedPrompt
      check "Active working directory path (this is the scriptorium plan worktree):" in capturedPrompt
      check "Only edit spec.md in this working directory." in capturedPrompt
      check "as the authoritative planning file." in capturedPrompt
      check "Inline convenience copy of `spec.md` from the plan worktree:" in capturedPrompt

      let specBody = readPlanFile(repoPath, "spec.md")
      check "# Integration Spec" in specBody
      check "- marker: integration-marker" in specBody

      let files = planTreeFiles(repoPath)
      check "spec.md" in files
      check "areas/01-out-of-scope.md" notin files

      let commits = latestPlanCommits(repoPath, 1)
      check commits.len == 1
      check commits[0] == "scriptorium: update spec from architect"
    )
