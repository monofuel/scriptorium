import
  std/[json, options, os, posix, times, unittest],
  acport,
  scriptorium/[agent_runner_types, guildhall_control, pause_flag, runtime_status],
  helpers

suite "owner verified native activity":
  setup:
    let repo = createTempDir("scriptorium-runtime-activity-", "")
    makeInitializedTestRepo(repo)
    acquireOrchestratorPidGuard(repo)
    installRuntimeActivityObserver(repo)
  teardown:
    clearRuntimeActivityObserver()
    releaseOrchestratorPidGuard(repo)
    removeDir(repo)

  test "synchronous architect and manager calls are visible without pool slots":
    writeRuntimeSnapshot(repo, "architect", @[], 1)
    for role in ["architect", "manager", "coder", "reviewer", "audit"]:
      let id = agentActivityStarted(AgentRunRequest(activityRole: role, activityTask: "Synthetic task",
        activityAreaId: "core", ticketId: "synthetic", acpAgent: "codex",
        model: "explicit-model", reasoningEffort: "high"))
      let status = guildhallStatus(repo)
      check status["agents"]["activityVerified"].getBool()
      check status["agents"]["agents"].len == 1
      let agent = status["agents"]["agents"][0]
      check agent["role"].getStr() == role
      check agent["task"].getStr() == "Synthetic task"
      check agent["state"].getStr() == "starting"
      check agent["model"].getStr() == "explicit-model"
      check agent["reasoningEffort"].getStr() == "high"
      check agent["nativeSessionId"].getStr() == ""
      agentActivityFinished(id, AgentRunResult(), false)
      check guildhallStatus(repo)["agents"]["agents"].len == 0
    check readVerifiedActivity(repo).get().recent.len == 4

  test "pool reservations are deduplicated and unlabeled reservations stay assigned":
    let slot = AgentSlot(role: arManager, ticketId: "manager-core", areaId: "core", startTime: epochTime())
    writeRuntimeSnapshot(repo, "managers", @[slot], 1)
    check guildhallStatus(repo)["agents"]["agents"][0]["state"].getStr() == "assigned"
    let id = agentActivityStarted(AgentRunRequest(activityRole: "manager", ticketId: "manager-core"))
    check guildhallStatus(repo)["agents"]["agents"].len == 1
    agentActivityFinished(id, AgentRunResult(), false)
    let status = guildhallStatus(repo)
    check status["agents"]["agents"].len == 1
    check status["agents"]["agents"][0]["state"].getStr() == "assigned"

  test "typed tool metadata excludes transcripts, commands and scoped URLs; heartbeats are not progress":
    let id = agentActivityStarted(AgentRunRequest(activityRole: "manager", activityTask: "Plan tickets"))
    let update = parseUpdate(%*{"sessionId": "native-synthetic", "update": {
      "sessionUpdate": "tool_call", "toolCallId": "tool1", "kind": "read", "status": "in_progress",
      "title": "private-command-sentinel", "rawInput": {"url": "http://localhost/scoped-secret"}}})
    agentActivityEvent(id, AgentStreamEvent(kind: agentEventTool, update: update,
      rawLine: "raw-private-data", text: "private-command-sentinel"))
    let before = readVerifiedActivity(repo).get().active[0]
    check before.nativeSessionId == "native-synthetic"
    check before.state == "tool"
    check before.lastEvent == "read"
    agentActivityEvent(id, AgentStreamEvent(kind: agentEventHeartbeat, text: "still alive"))
    let after = readVerifiedActivity(repo).get().active[0]
    check after.lastEventAt == before.lastEventAt
    let data = readFile(runtimeActivityPath(repo))
    for secret in ["private-command-sentinel", "scoped-secret", "raw-private-data", "still alive"]:
      check secret notin data
    agentActivityFinished(id, AgentRunResult(exitCode: 1, failureKind: failureCancelled), false)
    let recent = readVerifiedActivity(repo).get().recent[0]
    check recent.state == "cancelled"
    check recent.failureKind == "failureCancelled"

  test "active native calls prevent quiescence even when the loop's last snapshot was paused":
    writePauseFlag(repo)
    writeRuntimeSnapshot(repo, "paused", @[], 1, pauseObserved = true, quiescent = true)
    check guildhallStatus(repo)["orchestrator"]["quiescent"].getBool()
    let id = agentActivityStarted(AgentRunRequest(activityRole: "architect"))
    check not guildhallStatus(repo)["orchestrator"]["quiescent"].getBool()
    agentActivityFinished(id, AgentRunResult(), false)
    check guildhallStatus(repo)["orchestrator"]["quiescent"].getBool()

  test "foreign owners and reused process identities cannot claim live activity":
    discard agentActivityStarted(AgentRunRequest(activityRole: "manager"))
    var state = readVerifiedActivity(repo).get()
    state.ownerStartTicks += 1
    writeFile(runtimeActivityPath(repo), state.toJson())
    check readVerifiedActivity(repo).isNone
    check not guildhallStatus(repo)["agents"]["activityVerified"].getBool()
    check guildhallStatus(repo)["agents"]["agents"].len == 0
    state.ownerPid = getppid().int
    writeFile(runtimeActivityPath(repo), state.toJson())
    check readVerifiedActivity(repo).isNone

  test "work links require existing canonical plan documents and reject private or escaping paths":
    let plan = repo / ".scriptorium/worktrees/plan"
    createDir(plan / "areas")
    writeFile(plan / "spec.md", "# Spec")
    writeFile(plan / "areas/core.md", "# Core")
    writeFile(plan / "private.md", "Synthetic private data")
    check safeActivityWorkPath(repo, ".scriptorium/worktrees/plan/spec.md").len > 0
    check safeActivityWorkPath(repo, ".scriptorium/worktrees/plan/areas/core.md").len > 0
    check safeActivityWorkPath(repo, ".scriptorium/worktrees/plan/private.md") == ""
    check safeActivityWorkPath(repo, "../outside.md") == ""
    createSymlink(plan / "private.md", plan / "areas/escape.md")
    check safeActivityWorkPath(repo, ".scriptorium/worktrees/plan/areas/escape.md") == ""

  test "legacy status inventories committed headings without inventing calls or changing the worktree":
    discard withLockedPlanWorktree(repo, proc(plan: string): bool =
      ## Create synthetic committed work items and preserve an unrelated untracked file.
      writeFile(plan / "areas/core.md", "# Core hardware\n")
      writeFile(plan / "tickets/in-progress/0001-checks.md", "# Independent checks\n\n**Area:** core\n")
      gitRun(plan, "add", "areas/core.md", "tickets/in-progress/0001-checks.md")
      gitRun(plan, "commit", "-m", "synthetic work inventory")
      writeFile(plan / "retained.txt", "Preserve unrelated work.\n")
      true)
    removeFile(runtimeActivityPath(repo))
    writeRuntimeSnapshot(repo, "managers", @[], 1)
    let
      plan = managedPlanWorktreePath(repo)
      headBefore = gitRunCapture(repo, @["rev-parse", "scriptorium/plan"]).output
      status = guildhallStatus(repo)
    check not status["agents"]["activityVerified"].getBool()
    check status["agents"]["agents"].len == 0
    check status["workItems"]["areas"]["items"][0]["title"].getStr() == "Core hardware"
    check status["workItems"]["inProgressTickets"]["items"][0]["title"].getStr() == "Independent checks"
    check readFile(plan / "retained.txt") == "Preserve unrelated work.\n"
    check gitRunCapture(repo, @["rev-parse", "scriptorium/plan"]).output == headBefore
    check not fileExists(runtimeActivityPath(repo))
