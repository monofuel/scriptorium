import
  std/[locks, options, os, posix, strutils, tables, times],
  jsony,
  ./[agent_runner_types, git_ops, lock_management, logging, shared_state]

const
  RuntimeSnapshotFileName* = "orchestrator-runtime.json"
  RuntimeActivityFileName* = "orchestrator-activity.json"
  MaxRecentActivities = 4
  ActivityPublishSeconds = 1.0
  ProcStatStartTimeIndex = 19
    ## Index of `starttime` (field 22) among the fields after the command name.

type
  RuntimeAgent* = object
    id*: string
    role*: string
    task*: string
    workPath*: string
    ticketId*: string
    areaId*: string
    acpAgent*: string
    model*: string
    reasoningEffort*: string
    state*: string
    nativeSessionId*: string
    lastEvent*: string
    startedAt*: float
    lastEventAt*: float
    endedAt*: float
    failureKind*: string

  RuntimeSnapshot* = object
    ownerPid*: int
    ownerStartTicks*: int64
    phase*: string
    pauseObserved*: bool
    quiescent*: bool
    agents*: seq[RuntimeAgent]
    maxAgents*: int
    updatedAt*: float

  RuntimeActivitySnapshot* = object
    ownerPid*: int
    ownerStartTicks*: int64
    active*: seq[RuntimeAgent]
    recent*: seq[RuntimeAgent]
    updatedAt*: float

var
  activityLock: Lock
  activityLockInitialized = false
  activitySerial = 0
  activityStates: Table[string, RuntimeActivitySnapshot]

proc runtimeSnapshotPath*(repoPath: string): string =
  ## Return the orchestrator runtime snapshot path for one repository.
  result = managedRepoRootPath(repoPath) / RuntimeSnapshotFileName

proc runtimeActivityPath*(repoPath: string): string =
  ## Return the callback-owned activity file, separate from loop phase and slot reservations.
  managedRepoRootPath(repoPath) / RuntimeActivityFileName

proc safeActivityWorkPath*(repoPath, relative: string): string =
  ## Return an existing canonical plan document path, excluding private state and symlink escapes.
  if relative.len == 0 or relative.isAbsolute() or '\\' in relative: return ""
  for part in relative.split('/'):
    if part in ["", ".", ".."]: return ""
  if not fileExists(repoPath / relative): return ""
  try:
    let
      root = expandFilename(repoPath)
      plan = expandFilename(managedPlanWorktreePath(repoPath))
      resolved = expandFilename(root / relative)
      document = relativePath(resolved, plan).replace('\\', '/')
    if not plan.startsWith(root & DirSep) or not resolved.startsWith(plan & DirSep): return ""
    if document == "spec.md" or (document.endsWith(".md") and
        (document.startsWith("areas/") or document.startsWith("tickets/"))):
      result = relativePath(resolved, root).replace('\\', '/')
  except OSError:
    result = ""

proc processStartTicks*(pid: int): int64 =
  ## Return the kernel start time of a live process, or 0 when it cannot be read.
  ## The value comes from /proc and identifies one process instance across PID reuse.
  let statPath = "/proc/" & $pid & "/stat"
  if pid <= 0 or not fileExists(statPath):
    return 0
  let
    stat = readFile(statPath)
    fields = stat[stat.rfind(')') + 1 .. ^1].splitWhitespace()
  if fields.len > ProcStatStartTimeIndex:
    result = parseBiggestInt(fields[ProcStatStartTimeIndex])

proc processAlive*(pid: int): bool =
  ## Return true when a process with this PID exists.
  if pid <= 0:
    return false
  let rc = posix.kill(Pid(pid), cint(0))
  result = rc == 0 or (rc == -1 and errno == EPERM)

proc readOrchestratorPidFile*(repoPath: string): OrchestratorPidFile =
  ## Read the orchestrator PID file, returning PID 0 when it is absent or unrecognized.
  ## The guard writes JSON; a bare decimal PID is also accepted with timestamp 0.
  let pidPath = orchestratorPidPath(repoPath)
  if not fileExists(pidPath):
    return
  let raw = readFile(pidPath).strip()
  if raw.startsWith("{"):
    result = fromJson(raw, OrchestratorPidFile)
  elif raw.len > 0 and raw.allCharsInSet(Digits):
    result = OrchestratorPidFile(pid: parseInt(raw))

proc agentRoleName(role: AgentRole): string =
  ## Return the status name for an agent pool role.
  case role
  of arCoder: "coder"
  of arManager: "manager"
  of arAudit: "audit"

proc writeRuntimeSnapshot*(repoPath, phase: string, slots: seq[AgentSlot], maxAgents: int,
    pauseObserved = false, quiescent = false) =
  ## Atomically replace the runtime snapshot with the calling process as owner.
  ## Only the orchestrator loop owner calls this.
  let ownerPid = getCurrentProcessId()
  var snapshot = RuntimeSnapshot(ownerPid: ownerPid, ownerStartTicks: processStartTicks(ownerPid),
    phase: phase, pauseObserved: pauseObserved, quiescent: quiescent, maxAgents: maxAgents,
    updatedAt: epochTime())
  for slot in slots:
    snapshot.agents.add(RuntimeAgent(role: agentRoleName(slot.role), ticketId: slot.ticketId,
      areaId: slot.areaId, startedAt: slot.startTime))
  let path = runtimeSnapshotPath(repoPath)
  createDir(parentDir(path))
  atomicWriteFile(path, snapshot.toJson())

proc readVerifiedRuntime*(repoPath: string): Option[RuntimeSnapshot] =
  ## Return the runtime snapshot only when its owner is the live orchestrator named by the PID file.
  ## Missing files, another owner, a dead owner and a reused PID all yield none.
  let path = runtimeSnapshotPath(repoPath)
  if not fileExists(path):
    return none(RuntimeSnapshot)
  let
    snapshot = fromJson(readFile(path), RuntimeSnapshot)
    owner = readOrchestratorPidFile(repoPath)
  if owner.pid > 0 and snapshot.ownerPid == owner.pid and snapshot.ownerStartTicks > 0 and
      processAlive(owner.pid) and processStartTicks(owner.pid) == snapshot.ownerStartTicks:
    result = some(snapshot)

proc mergeQueueIdle*(repoPath: string): bool =
  ## Return true when the committed plan has no pending merge item and no active marker.
  let
    pending = runCommandCapture(repoPath, "git", @["ls-tree", "--name-only",
      PlanBranch & ":" & PlanMergeQueuePendingDir])
    active = runCommandCapture(repoPath, "git", @["show", PlanBranch & ":" & PlanMergeQueueActivePath])
  var pendingCount = 0
  if pending.exitCode == 0:
    for line in pending.output.splitLines():
      if line.strip().endsWith(".md"): inc pendingCount
  let activeSet = active.exitCode == 0 and active.output.strip().len > 0
  result = pendingCount == 0 and not activeSet

proc publishActivity(repoPath: string) =
  ## Publish callback observations under the activity lock without changing the agent's outcome.
  var state = activityStates[repoPath]
  state.updatedAt = epochTime()
  activityStates[repoPath] = state
  let path = runtimeActivityPath(repoPath)
  try:
    createDir(path.parentDir)
    atomicWriteFile(path, state.toJson())
  except CatchableError as error:
    logWarn("runtime activity unavailable: " & error.msg)
    try:
      if fileExists(path): removeFile(path)
    except CatchableError as cleanupError:
      logWarn("cannot remove stale runtime activity: " & cleanupError.msg)

proc readVerifiedActivity*(repoPath: string): Option[RuntimeActivitySnapshot] =
  ## Return activity only when it belongs to the live PID and kernel start time in the run guard.
  let path = runtimeActivityPath(repoPath)
  if not fileExists(path): return none(RuntimeActivitySnapshot)
  let
    state = fromJson(readFile(path), RuntimeActivitySnapshot)
    owner = readOrchestratorPidFile(repoPath)
  if owner.pid > 0 and state.ownerPid == owner.pid and state.ownerStartTicks > 0 and
      processAlive(owner.pid) and processStartTicks(owner.pid) == state.ownerStartTicks:
    result = some(state)

proc observeActivity(repoPath, id: string, event: AgentStreamEvent) =
  ## Record typed native activity, excluding heartbeats, diagnostics and transcript contents.
  if event.kind == agentEventHeartbeat: return
  withLock activityLock:
    var state = activityStates[repoPath]
    for agent in state.active.mitems:
      if agent.id != id: continue
      let previous = agent
      if event.update.sessionId.len > 0: agent.nativeSessionId = event.update.sessionId
      case event.kind
      of agentEventReasoning:
        agent.state = "thinking"
        agent.lastEvent = "reasoning"
      of agentEventMessage:
        agent.state = "answering"
        agent.lastEvent = "message"
      of agentEventTool:
        agent.state = if event.update.tool.status in ["pending", "in_progress"]: "tool"
          else: "awaiting_output"
        agent.lastEvent = if event.update.tool.kind in ["read", "edit", "delete", "move", "execute", "search", "fetch"]:
            event.update.tool.kind else: "tool"
      of agentEventPlan:
        agent.state = "planning"
        agent.lastEvent = "plan"
      of agentEventStatus:
        agent.state = "awaiting_output"
        agent.lastEvent = "status"
      else: discard
      if event.kind != agentEventUnknown: agent.lastEventAt = epochTime()
      let changed = agent.state != previous.state or agent.nativeSessionId != previous.nativeSessionId or
        agent.lastEvent != previous.lastEvent
      activityStates[repoPath] = state
      if changed or epochTime() - state.updatedAt >= ActivityPublishSeconds:
        publishActivity(repoPath)
      break

proc finishActivity(repoPath, id: string, response: AgentRunResult, raised: bool) =
  ## Remove the active call and retain a bounded terminal summary without prompts or errors containing secrets.
  withLock activityLock:
    var state = activityStates[repoPath]
    for index, current in state.active:
      if current.id != id: continue
      var finished = current
      finished.endedAt = epochTime()
      if response.sessionId.len > 0: finished.nativeSessionId = response.sessionId
      finished.failureKind = if raised: "exception" else: $response.failureKind
      finished.state = if raised or response.exitCode != 0: "failed" else: "completed"
      if response.failureKind == failureCancelled: finished.state = "cancelled"
      state.recent.add(finished)
      if state.recent.len > MaxRecentActivities: state.recent.delete(0)
      state.active.delete(index)
      break
    activityStates[repoPath] = state
    publishActivity(repoPath)

proc installRuntimeActivityObserver*(repoPath: string) =
  ## Observe the existing ACP execution boundary without wrapping or replacing native conversation runners.
  if not activityLockInitialized:
    initLock(activityLock)
    activityLockInitialized = true
  withLock activityLock:
    activityStates[repoPath] = RuntimeActivitySnapshot(ownerPid: getCurrentProcessId(),
      ownerStartTicks: processStartTicks(getCurrentProcessId()))
    publishActivity(repoPath)
  agentActivityStarted = proc(request: AgentRunRequest): string =
    ## Record an actual native invocation before setup starts.
    var id: string
    withLock activityLock:
      inc activitySerial
      id = $getCurrentProcessId() & "-" & $activitySerial
      var state = activityStates[repoPath]
      let now = epochTime()
      state.active.add(RuntimeAgent(id: id,
        role: (if request.activityRole.len > 0: request.activityRole else: "unknown"),
        task: request.activityTask.substr(0, 199), workPath: safeActivityWorkPath(repoPath, request.activityWorkPath),
        ticketId: request.ticketId,
        areaId: request.activityAreaId, acpAgent: request.acpAgent,
        model: request.model, reasoningEffort: request.reasoningEffort,
        state: "starting", startedAt: now))
      activityStates[repoPath] = state
      publishActivity(repoPath)
    result = id
  agentActivityEvent = proc(id: string, event: AgentStreamEvent) =
    ## Record native updates without transcript data or synthetic progress.
    observeActivity(repoPath, id, event)
  agentActivityFinished = proc(id: string, response: AgentRunResult, raised: bool) =
    ## Finish one observed native invocation on success, failure or exception.
    finishActivity(repoPath, id, response, raised)

proc clearRuntimeActivityObserver*() =
  ## Detach observers after all orchestrator workers have joined.
  agentActivityStarted = nil
  agentActivityEvent = nil
  agentActivityFinished = nil
