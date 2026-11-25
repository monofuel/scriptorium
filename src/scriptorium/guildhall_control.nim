import
  std/[json, options, os, strutils, times],
  jsony,
  ./[config, dashboard, git_ops, lock_management, pause_flag, runtime_status, shared_state]

const
  ControlUsage* = "Usage: scriptorium guildhall-control start|pause|status"
  MaxWorkItems = 32

proc countPlanTickets(repoPath, directory: string): int =
  ## Count committed ticket files without touching the shared plan worktree.
  let listing = runCommandCapture(repoPath, "git", @["ls-tree", "--name-only",
    PlanBranch & ":" & directory])
  if listing.exitCode == 0:
    for line in listing.output.splitLines():
      if line.strip().endsWith(".md"): inc result

proc runtimeAgentJson(agent: RuntimeAgent, assigned = false): JsonNode =
  ## Render safe role and task metadata from an observed call or a pool reservation.
  let endTime = if agent.endedAt > 0: agent.endedAt else: epochTime()
  let elapsed = formatUptime(int64(endTime - agent.startedAt))
  %*{"id": agent.id, "role": agent.role, "ticketId": agent.ticketId, "areaId": agent.areaId,
    "task": agent.task, "workPath": agent.workPath, "acpAgent": agent.acpAgent, "model": agent.model,
    "reasoningEffort": agent.reasoningEffort, "state": (if assigned: "assigned" else: agent.state),
    "nativeSessionId": agent.nativeSessionId, "lastEvent": agent.lastEvent,
    "lastEventAt": agent.lastEventAt, "startedAt": agent.startedAt, "endedAt": agent.endedAt,
    "failureKind": agent.failureKind, "elapsed": elapsed,
    "status": (if assigned: "assigned" elif agent.endedAt > 0: agent.state else: "running")}

proc runtimeAgentsJson(snapshot: RuntimeSnapshot, activity: Option[RuntimeActivitySnapshot]): JsonNode =
  ## Combine actual synchronous and asynchronous native calls with unmatched pool reservations.
  result = newJArray()
  if activity.isSome:
    for agent in activity.get().active: result.add(runtimeAgentJson(agent))
  for agent in snapshot.agents:
    var observed = false
    if activity.isSome:
      for current in activity.get().active:
        if current.role == agent.role and current.ticketId == agent.ticketId: observed = true
    if not observed: result.add(runtimeAgentJson(agent, assigned = true))

proc committedWorkItems(repoPath, directory, kind: string): JsonNode =
  ## Read a bounded heading inventory from committed plan documents without inferring running calls.
  result = %*{"source": "committed_plan", "items": [], "truncated": false}
  let listing = runCommandCapture(repoPath, "git", @["ls-tree", "--name-only", PlanBranch & ":" & directory])
  if listing.exitCode != 0: return
  for filename in listing.output.splitLines():
    if not filename.endsWith(".md"): continue
    if result["items"].len >= MaxWorkItems:
      result["truncated"] = %true
      break
    let relative = directory / filename
    let content = runCommandCapture(repoPath, "git", @["show", PlanBranch & ":" & relative])
    if content.exitCode != 0: continue
    let workPath = safeActivityWorkPath(repoPath, relativePath(managedPlanWorktreePath(repoPath) / relative, repoPath))
    result["items"].add(%*{"kind": kind, "path": relative,
      "title": dashboard.parseTitleFromTicketContent(content.output), "workPath": workPath})

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
    activity = readVerifiedActivity(repoPath)
    snapshot = runtime.get(RuntimeSnapshot())
    quiescent = verified and status.paused and snapshot.pauseObserved and snapshot.quiescent and
      (activity.isNone or activity.get().active.len == 0)
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
    "agents": {"agents": runtimeAgentsJson(snapshot, activity),
      "maxAgents": loadConfig(repoPath).concurrency.maxAgents,
      "source": (if verified or activity.isSome: "runtime" else: "unavailable"),
      "activityVerified": activity.isSome, "recent": []},
    "mergeQueue": {"pending": [], "active": nil, "recentOutcomes": []},
    "workItems": {"areas": {"source": "committed_plan", "items": [], "truncated": false},
      "inProgressTickets": {"source": "committed_plan", "items": [], "truncated": false}},
  }
  if activity.isSome:
    for agent in activity.get().recent: result["agents"]["recent"].add(runtimeAgentJson(agent))
  if planReady:
    result["workItems"]["areas"] = committedWorkItems(repoPath, PlanAreasDir, "area")
    result["workItems"]["inProgressTickets"] = committedWorkItems(repoPath, PlanTicketsInProgressDir, "ticket")
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
