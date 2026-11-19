import
  std/[json, options, os, strutils, times],
  jsony,
  ./[config, dashboard, git_ops, lock_management, pause_flag, runtime_status, shared_state]

const
  ControlUsage* = "Usage: scriptorium guildhall-control start|pause|status"

proc countPlanTickets(repoPath, directory: string): int =
  ## Count committed ticket files without touching the shared plan worktree.
  let listing = runCommandCapture(repoPath, "git", @["ls-tree", "--name-only",
    PlanBranch & ":" & directory])
  if listing.exitCode == 0:
    for line in listing.output.splitLines():
      if line.strip().endsWith(".md"): inc result

proc runtimeAgentsJson(snapshot: RuntimeSnapshot): JsonNode =
  ## Render the pool workers recorded by a verified runtime snapshot.
  result = newJArray()
  let now = epochTime()
  for agent in snapshot.agents:
    let elapsed = formatUptime(int64(now - agent.startedAt))
    result.add(%*{"role": agent.role, "ticketId": agent.ticketId, "areaId": agent.areaId,
      "elapsed": elapsed, "status": "running"})

proc guildhallStatus*(repoPath: string): JsonNode =
  ## Build structured orchestrator, ticket, agent and merge state from shared durable records.
  ## Active agents and quiescence come only from a runtime snapshot owned by the live orchestrator.
  let
    status = getApiStatus(repoPath)
    adminLock = managedAdminLockPath(repoPath)
    adminHeld = dirExists(adminLock) and not lockPathIsStale(adminLock)
    planReady = hasPlanBranch(repoPath)
    runtime = readVerifiedRuntime(repoPath)
    verified = runtime.isSome
    snapshot = runtime.get(RuntimeSnapshot())
    quiescent = verified and status.paused and snapshot.pauseObserved and snapshot.quiescent
  result = %*{
    "repo": repoPath,
    "planBranch": planReady,
    "orchestrator": {"running": status.pidAlive, "paused": status.paused,
      "admitsNewWork": status.pidAlive and not status.paused,
      "runtimeVerified": verified, "phase": snapshot.phase,
      "pauseObserved": snapshot.pauseObserved, "quiescent": quiescent,
      "uptime": status.uptime.get(""), "loopIteration": status.loopIteration},
    "architect": {"turnActive": adminHeld,
      "adminLockPid": (if adminHeld: lockHolderPid(adminLock) else: 0)},
    "tickets": {"open": 0, "inProgress": 0, "done": 0, "stuck": 0, "inProgressTickets": []},
    "agents": {"agents": runtimeAgentsJson(snapshot),
      "maxAgents": loadConfig(repoPath).concurrency.maxAgents,
      "source": (if verified: "runtime" else: "unavailable")},
    "mergeQueue": {"pending": [], "active": nil, "recentOutcomes": []},
  }
  if planReady:
    var inProgressTickets = newJArray()
    for ticket in getApiAgents(repoPath).agents:
      inProgressTickets.add(%*{"ticketId": ticket.ticketId, "areaId": ticket.areaId})
    result["tickets"] = %*{
      "open": countPlanTickets(repoPath, PlanTicketsOpenDir),
      "inProgress": countPlanTickets(repoPath, PlanTicketsInProgressDir),
      "done": countPlanTickets(repoPath, PlanTicketsDoneDir),
      "stuck": countPlanTickets(repoPath, PlanTicketsStuckDir),
      "inProgressTickets": inProgressTickets}
    result["mergeQueue"] = parseJson(getApiQueue(repoPath).toJson())

proc runGuildhallControl*(repoPath: string, args: seq[string]) =
  ## Apply one admission command and print the resulting structured status as JSON.
  if args.len != 1 or args[0] notin ["start", "pause", "status"]:
    raise newException(ValueError, ControlUsage)
  if not hasPlanBranch(repoPath):
    raise newException(ValueError, "workspace is not initialized; run `scriptorium init` first")
  case args[0]
  of "start":
    if not getApiStatus(repoPath).pidAlive:
      raise newException(ValueError, "no orchestrator is running for this repository; start `scriptorium run --paused` first")
    removePauseFlag(repoPath)
  of "pause":
    writePauseFlag(repoPath)
  else: discard
  stdout.writeLine($guildhallStatus(repoPath))
