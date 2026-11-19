import
  std/[options, os, posix, strutils, times],
  jsony,
  ./[git_ops, lock_management, shared_state]

const
  RuntimeSnapshotFileName* = "orchestrator-runtime.json"
  ProcStatStartTimeIndex = 19
    ## Index of `starttime` (field 22) among the fields after the command name.

type
  RuntimeAgent* = object
    role*: string
    ticketId*: string
    areaId*: string
    startedAt*: float

  RuntimeSnapshot* = object
    ownerPid*: int
    ownerStartTicks*: int64
    phase*: string
    pauseObserved*: bool
    quiescent*: bool
    agents*: seq[RuntimeAgent]
    maxAgents*: int
    updatedAt*: float

proc runtimeSnapshotPath*(repoPath: string): string =
  ## Return the orchestrator runtime snapshot path for one repository.
  result = managedRepoRootPath(repoPath) / RuntimeSnapshotFileName

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
