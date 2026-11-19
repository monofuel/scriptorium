## Tests for the orchestrator runtime snapshot, owner verification and Guildhall quiescence.

import
  std/[options, posix, times],
  scriptorium/[agent_pool, guildhall_control, pause_flag, runtime_status, shared_state],
  helpers

const
  DeadPid = 999_999_999
  HeldWorkerMs = 2000
  ManagerArea = "area-one"

proc heldManagerWorker(args: AgentThreadArgs) {.thread.} =
  ## Hold one pool slot briefly, then report a manager completion.
  sleep(HeldWorkerMs)
  sendPoolResult(AgentPoolCompletionResult(role: arManager, ticketId: args.ticketId, areaId: args.areaId))

proc snapshotOnDisk(repoPath: string): RuntimeSnapshot =
  ## Read the raw runtime snapshot without owner verification.
  result = fromJson(readFile(runtimeSnapshotPath(repoPath)), RuntimeSnapshot)

proc writeQuiescentSnapshot(repoPath: string) =
  ## Record the snapshot a drained paused loop writes.
  writeRuntimeSnapshot(repoPath, "paused", @[], 1, pauseObserved = true, quiescent = true)

proc commitMergeQueueFile(repoPath, relPath, content: string) =
  ## Commit one merge queue file on the plan branch, creating its directory.
  withPlanWorktree(repoPath, "merge_queue_file", proc(planPath: string) =
    createDir(parentDir(planPath / relPath))
    writeFile(planPath / relPath, content)
    runCmdOrDie("git -C " & quoteShell(planPath) & " add queue")
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m test-merge-queue-file")
  )

suite "orchestrator PID file":
  test "the guard's JSON PID file reports a running orchestrator":
    withTempRepo("runtime_pid_json_", proc(repo: string) =
      acquireOrchestratorPidGuard(repo)
      defer: releaseOrchestratorPidGuard(repo)
      check readFile(orchestratorPidPath(repo)).strip().startsWith("{")
      check readOrchestratorPidFile(repo).pid == getCurrentProcessId()
      check guildhallStatus(repo)["orchestrator"]["running"].getBool()
    )

  test "a JSON PID file for a dead process is not running":
    withTempRepo("runtime_pid_dead_", proc(repo: string) =
      createDir(managedRepoRootPath(repo))
      writeFile(orchestratorPidPath(repo), OrchestratorPidFile(pid: DeadPid, timestamp: 1.0).toJson())
      check not guildhallStatus(repo)["orchestrator"]["running"].getBool()
    )

suite "guildhall runtime status":
  test "an active manager is reported with zero in-progress coding tickets":
    withInitializedTempRepo("runtime_manager_", proc(repo: string) =
      acquireOrchestratorPidGuard(repo)
      defer: releaseOrchestratorPidGuard(repo)
      let slot = AgentSlot(role: arManager, ticketId: "manager-" & ManagerArea, areaId: ManagerArea,
        startTime: epochTime())
      writeRuntimeSnapshot(repo, "managers", @[slot], 2)
      let status = guildhallStatus(repo)
      check status["tickets"]["inProgress"].getInt() == 0
      check status["agents"]["source"].getStr() == "runtime"
      check status["agents"]["agents"].len == 1
      check status["agents"]["agents"][0]["role"].getStr() == "manager"
      check status["agents"]["agents"][0]["areaId"].getStr() == ManagerArea
      check status["orchestrator"]["phase"].getStr() == "managers"
      check not status["orchestrator"]["quiescent"].getBool()
    )

  test "in-progress tickets are not labeled running without a snapshot":
    withInitializedTempRepo("runtime_inferred_", proc(repo: string) =
      addTicketToPlan(repo, "in-progress", "0007-thing.md", "# Thing\n\n**Area:** core\n")
      let status = guildhallStatus(repo)
      check status["agents"]["source"].getStr() == "unavailable"
      check status["agents"]["agents"].len == 0
      check status["tickets"]["inProgressTickets"].len == 1
      check status["tickets"]["inProgressTickets"][0]["ticketId"].getStr() == "0007"
    )

  test "a pause the loop has not observed is not quiescent":
    withTempRepo("runtime_pause_pending_", proc(repo: string) =
      acquireOrchestratorPidGuard(repo)
      defer: releaseOrchestratorPidGuard(repo)
      writeRuntimeSnapshot(repo, "coding", @[], 1)
      writePauseFlag(repo)
      let orchestrator = guildhallStatus(repo)["orchestrator"]
      check orchestrator["paused"].getBool()
      check not orchestrator["pauseObserved"].getBool()
      check not orchestrator["quiescent"].getBool()
    )

  test "an observed, drained pause is quiescent only while the pause flag is set":
    withTempRepo("runtime_quiescent_", proc(repo: string) =
      acquireOrchestratorPidGuard(repo)
      defer: releaseOrchestratorPidGuard(repo)
      writePauseFlag(repo)
      writeQuiescentSnapshot(repo)
      check guildhallStatus(repo)["orchestrator"]["quiescent"].getBool()
      removePauseFlag(repo)
      check not guildhallStatus(repo)["orchestrator"]["quiescent"].getBool()
    )

  test "missing, dead, reused and foreign owners are not quiescent":
    withTempRepo("runtime_stale_", proc(repo: string) =
      writePauseFlag(repo)
      writeQuiescentSnapshot(repo)
      check not guildhallStatus(repo)["orchestrator"]["runtimeVerified"].getBool()
      check not guildhallStatus(repo)["orchestrator"]["quiescent"].getBool()

      var snapshot = snapshotOnDisk(repo)
      snapshot.ownerPid = DeadPid
      writeFile(runtimeSnapshotPath(repo), snapshot.toJson())
      writeFile(orchestratorPidPath(repo), OrchestratorPidFile(pid: DeadPid, timestamp: 1.0).toJson())
      check not guildhallStatus(repo)["orchestrator"]["quiescent"].getBool()

      acquireOrchestratorPidGuard(repo)
      defer: releaseOrchestratorPidGuard(repo)
      writeQuiescentSnapshot(repo)
      check guildhallStatus(repo)["orchestrator"]["quiescent"].getBool()
      snapshot = snapshotOnDisk(repo)
      snapshot.ownerStartTicks = snapshot.ownerStartTicks + 1
      writeFile(runtimeSnapshotPath(repo), snapshot.toJson())
      check not guildhallStatus(repo)["orchestrator"]["quiescent"].getBool()

      writeQuiescentSnapshot(repo)
      writeFile(orchestratorPidPath(repo), OrchestratorPidFile(pid: int(getppid()), timestamp: 1.0).toJson())
      check guildhallStatus(repo)["orchestrator"]["running"].getBool()
      check not guildhallStatus(repo)["orchestrator"]["quiescent"].getBool()
    )

  test "pending or active merges keep the queue busy":
    withInitializedTempRepo("runtime_merge_", proc(repo: string) =
      check mergeQueueIdle(repo)
      commitMergeQueueFile(repo, PlanMergeQueueActivePath, "queue/merge/pending/0001-item.md\n")
      check not mergeQueueIdle(repo)
      commitMergeQueueFile(repo, PlanMergeQueueActivePath, "")
      check mergeQueueIdle(repo)
      commitMergeQueueFile(repo, PlanMergeQueuePendingDir & "/0001-item.md", "**Ticket ID:** 0001\n")
      check not mergeQueueIdle(repo)
    )

suite "orchestrator loop runtime snapshot":
  setup:
    tickSleepOverrideMs = 0

  teardown:
    tickSleepOverrideMs = -1

  test "a paused, drained tick records observed quiescence":
    withInitializedTempRepo("runtime_loop_paused_", proc(repo: string) =
      writePauseFlag(repo)
      runOrchestratorForTicks(repo, 1, noopRunner)
      let snapshot = snapshotOnDisk(repo)
      check snapshot.ownerPid == getCurrentProcessId()
      check snapshot.ownerStartTicks == processStartTicks(getCurrentProcessId())
      check snapshot.phase == "paused"
      check snapshot.pauseObserved
      check snapshot.quiescent
    )

  test "a paused tick with a pool worker is draining, not quiescent":
    withInitializedTempRepo("runtime_loop_worker_", proc(repo: string) =
      writePauseFlag(repo)
      startManagerAgentAsync(repo, ManagerArea, "", "", 1, 1, heldManagerWorker)
      runOrchestratorForTicks(repo, 1, noopRunner)
      let snapshot = snapshotOnDisk(repo)
      check snapshot.phase == "paused-draining"
      check snapshot.pauseObserved
      check snapshot.agents.len == 1
      check snapshot.agents[0].role == "manager"
      check not snapshot.quiescent
    )

  test "an unpaused tick replaces a stale quiescent snapshot before admitting work":
    withInitializedTempRepo("runtime_loop_unpaused_", proc(repo: string) =
      addPassingMakefile(repo)
      writeQuiescentSnapshot(repo)
      runOrchestratorForTicks(repo, 1, noopRunner)
      let snapshot = snapshotOnDisk(repo)
      check snapshot.phase == "between-ticks"
      check not snapshot.pauseObserved
      check not snapshot.quiescent
    )
