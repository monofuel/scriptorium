import
  std/[strformat, times],
  ./[agent_runner, logging, shared_state, ticket_metadata]

const
  ManagerTicketIdPrefix = "manager-"

type
  AgentPoolCompletionResult* = object
    role*: AgentRole
    ticketId*: string
    areaId*: string
    result*: AgentRunResult
    managerResult*: seq[string]

var
  agentPoolResultChan: Channel[AgentPoolCompletionResult]
  agentPoolResultChanOpen = false
  runningPoolSlots: seq[AgentSlot]
  runningPoolThreadPtrs: seq[ptr Thread[AgentThreadArgs]]

proc ensurePoolResultChanOpen*() =
  ## Open the agent pool result channel once.
  if not agentPoolResultChanOpen:
    agentPoolResultChan.open()
    agentPoolResultChanOpen = true

proc sendPoolResult*(completion: AgentPoolCompletionResult) =
  ## Send a completion result to the pool channel from a worker thread.
  ensurePoolResultChanOpen()
  agentPoolResultChan.send(completion)

proc runningAgentCount*(): int =
  ## Return the number of currently running agent slots.
  result = runningPoolSlots.len

proc runningAgentCountByRole*(role: AgentRole): int =
  ## Return the number of running agent slots for a specific role.
  for slot in runningPoolSlots:
    if slot.role == role:
      inc result

proc emptySlotCount*(maxAgents: int): int =
  ## Return the number of available agent slots.
  result = maxAgents - runningPoolSlots.len

proc startAgentAsync*(
  role: AgentRole,
  repoPath: string,
  assignment: TicketAssignment,
  ticketId: string,
  areaId: string,
  maxAgents: int,
  workerThread: proc(args: AgentThreadArgs) {.thread.},
) =
  ## Start an agent in a background thread for the given role and assignment.
  ensurePoolResultChanOpen()
  let slot = AgentSlot(
    role: role,
    ticketId: ticketId,
    areaId: areaId,
    branch: assignment.branch,
    worktree: assignment.worktree,
    startTime: epochTime(),
  )
  runningPoolSlots.add(slot)
  let threadPtr = create(Thread[AgentThreadArgs])
  let args: AgentThreadArgs = (
    repoPath: repoPath,
    assignment: assignment,
    ticketId: ticketId,
    areaId: areaId,
    areaContent: "",
    planPath: "",
    nextId: 0,
  )
  createThread(threadPtr[], workerThread, args)
  runningPoolThreadPtrs.add(threadPtr)
  let running = runningPoolSlots.len
  let roleStr = $role
  logInfo(&"agent slots: {running}/{maxAgents} ({roleStr} {ticketId} started)")

proc startCodingAgentAsync*(repoPath: string, assignment: TicketAssignment, maxAgents: int, workerThread: proc(args: AgentThreadArgs) {.thread.}) =
  ## Start a coding agent in a background thread for the given assignment.
  let ticketId = ticketIdFromTicketPath(assignment.inProgressTicket)
  startAgentAsync(arCoder, repoPath, assignment, ticketId, "", maxAgents, workerThread)

proc startManagerAgentAsync*(repoPath: string, areaId: string, areaContent: string,
    planPath: string, nextId: int, maxAgents: int,
    workerThread: proc(args: AgentThreadArgs) {.thread.}) =
  ## Start a manager agent in a background thread for a single area.
  ensurePoolResultChanOpen()
  let ticketId = ManagerTicketIdPrefix & areaId
  let slot = AgentSlot(
    role: arManager,
    ticketId: ticketId,
    areaId: areaId,
    branch: "",
    worktree: "",
    startTime: epochTime(),
  )
  runningPoolSlots.add(slot)
  let threadPtr = create(Thread[AgentThreadArgs])
  let args: AgentThreadArgs = (
    repoPath: repoPath,
    assignment: TicketAssignment(),
    ticketId: ticketId,
    areaId: areaId,
    areaContent: areaContent,
    planPath: planPath,
    nextId: nextId,
  )
  createThread(threadPtr[], workerThread, args)
  runningPoolThreadPtrs.add(threadPtr)
  let running = runningPoolSlots.len
  logInfo(&"agent slots: {running}/{maxAgents} (arManager {areaId} started)")

proc checkCompletedAgents*(): seq[AgentPoolCompletionResult] =
  ## Poll the result channel for completed agents and clean up their slots and threads.
  ensurePoolResultChanOpen()
  while true:
    let (hasData, completion) = agentPoolResultChan.tryRecv()
    if not hasData:
      break
    result.add(completion)
    var slotIdx = -1
    for i, slot in runningPoolSlots:
      if completion.role == arCoder and slot.ticketId == completion.ticketId:
        slotIdx = i
        break
      elif completion.role == arManager and slot.areaId == completion.areaId:
        slotIdx = i
        break
    if slotIdx >= 0:
      runningPoolSlots.delete(slotIdx)
      joinThread(runningPoolThreadPtrs[slotIdx][])
      dealloc(runningPoolThreadPtrs[slotIdx])
      runningPoolThreadPtrs.delete(slotIdx)

proc joinAllAgentThreads*() =
  ## Block until all running agent threads complete and clean up.
  for i in 0..<runningPoolThreadPtrs.len:
    joinThread(runningPoolThreadPtrs[i][])
    dealloc(runningPoolThreadPtrs[i])
  runningPoolSlots.setLen(0)
  runningPoolThreadPtrs.setLen(0)
