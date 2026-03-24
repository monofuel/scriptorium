## Tests for orchestrator planning: spec updates, invariants, bootstrap.

import
  std/[algorithm, json, locks, os, osproc, sequtils, sha1, strformat, strutils, tables, tempfiles, times, unittest],
  jsony,
  scriptorium/[agent_runner, config, init, logging, orchestrator, ticket_metadata],
  helpers

suite "orchestrator plan spec update":
  test "updateSpecFromArchitect runs in plan worktree, reads repo path, and commits":
    let tmp = getTempDir() / "scriptorium_test_plan_update_spec"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
    addTicketToPlan(tmp, "done", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    expect ValueError:
      validateTicketStateInvariant(tmp)

  test "transition commit invariant passes for orchestrator-managed state moves":
    let tmp = getTempDir() / "scriptorium_test_invariant_transition_pass"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    discard assignOldestOpenTicket(tmp)
    validateTransitionCommitInvariant(tmp)

  test "transition commit invariant fails for non-orchestrator ticket move commit":
    let tmp = getTempDir() / "scriptorium_test_invariant_transition_fail"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
    moveTicketStateInPlan(tmp, "open", "in-progress", "0001-first.md")

    expect ValueError:
      validateTransitionCommitInvariant(tmp)

  test "simulated crash during ticket move keeps prior valid state":
    let tmp = getTempDir() / "scriptorium_test_invariant_no_partial_move_on_crash"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    let spec = loadSpecFromPlan(tmp)
    check "scriptorium plan" in spec

  test "missing spec raises error":
    let tmp = getTempDir() / "scriptorium_test_plan_missing_spec"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    removeSpecFromPlan(tmp)

    expect ValueError:
      discard loadSpecFromPlan(tmp)

  test "areas missing is true for blank plan and false when area exists":
    let tmp = getTempDir() / "scriptorium_test_areas_missing"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    check areasMissing(tmp)
    addAreaToPlan(tmp, "01-cli.md", "# Area 01\n")
    check not areasMissing(tmp)

  test "sync areas calls architect with configured model and spec":
    let tmp = getTempDir() / "scriptorium_test_sync_areas_call"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addAreaToPlan(tmp, "01-cli.md", "# Area 01\n")
    addAreaToPlan(tmp, "02-core.md", "# Area 02\n")
    addTicketToPlan(tmp, "open", "0001-cli-ticket.md", "# Ticket\n\n**Area:** 01-cli\n")

    let needed = areasNeedingTickets(tmp)
    check "areas/02-core.md" in needed
    check "areas/01-cli.md" notin needed
