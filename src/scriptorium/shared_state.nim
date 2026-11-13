import
  std/[locks, strformat, tables, times],
  ./[agent_runner, agent_usage, logging]

export agent_usage

const
  PlanAreasDir* = "areas"
  PlanTicketsOpenDir* = "tickets/open"
  PlanTicketsInProgressDir* = "tickets/in-progress"
  PlanTicketsDoneDir* = "tickets/done"
  PlanTicketsStuckDir* = "tickets/stuck"
  PlanMergeQueueDir* = "queue/merge"
  PlanMergeQueuePendingDir* = "queue/merge/pending"
  PlanMergeQueueActivePath* = "queue/merge/active.md"
  PlanSpecPath* = "spec.md"
  PlanQuestsDir* = "quests"
  PlanQuestActivePath* = "quests/active.md"
  PlanQuestVerdictPath* = "quests/active-verdict.json"
  PlanQuestsDoneDir* = "quests/done"
  DefaultAgentAttempt* = 1
  DefaultAgentMaxAttempts* = 2
  DefaultLocalEndpoint* = "http://127.0.0.1:8097"
  ValidDifficulties* = ["trivial", "easy", "medium", "hard", "complex"]

type
  OrchestratorEndpoint* = object
    address*: string
    port*: int

  AreaDocument* = object
    path*: string
    content*: string

  ArchitectAreaGenerator* = proc(model: string, spec: string): seq[AreaDocument]

  TicketDocument* = object
    slug*: string
    content*: string

  PlanTurn* = object
    role*: string
    text*: string

  PlanSessionInput* = proc(): string
    ## Returns the next line of input. Raises EOFError to end the session.

  TicketAssignment* = object
    openTicket*: string
    inProgressTicket*: string
    branch*: string
    worktree*: string

  ActiveTicketWorktree* = object
    ticketPath*: string
    ticketId*: string
    branch*: string
    worktree*: string

  InProgressTicketElapsed* = object
    ticketId*: string
    elapsed*: string

  DoneTicketSummary* = object
    ticketId*: string
    outcome*: string
    wallTimeSeconds*: int

  BlockedTicket* = object
    ticketId*: string
    cycleIds*: seq[string]

  WaitingTicket* = object
    ticketId*: string
    dependsOn*: seq[string]

  OrchestratorStatus* = object
    openTickets*: int
    inProgressTickets*: int
    doneTickets*: int
    activeTicketPath*: string
    activeTicketId*: string
    activeTicketBranch*: string
    activeTicketWorktree*: string
    inProgressElapsed*: seq[InProgressTicketElapsed]
    recentDoneTickets*: seq[DoneTicketSummary]
    firstAttemptSuccessCount*: int
    totalDoneWithAttempts*: int
    stuckTickets*: int
    blockedTickets*: seq[BlockedTicket]
    waitingTickets*: seq[WaitingTicket]

  MergeQueueItem* = object
    pendingPath*: string
    ticketPath*: string
    ticketId*: string
    branch*: string
    worktree*: string
    summary*: string

  HealthCacheEntry* = object
    healthy*: bool
    timestamp*: string
    test_exit_code*: int
    integration_test_exit_code*: int
    test_wall_seconds*: int
    integration_test_wall_seconds*: int

  SessionStats* = object
    startTime*: float
    totalTicks*: int
    ticketsCompleted*: int
    ticketsReopened*: int
    ticketsParked*: int
    mergeQueueProcessed*: int
    firstAttemptSuccessCount*: int
    completedTicketWalls*: seq[float]
    completedCodingWalls*: seq[float]
    completedTestWalls*: seq[float]

  AgentRole* = enum
    arCoder
    arManager
    arAudit

  AgentSlot* = object
    role*: AgentRole
    ticketId*: string
    areaId*: string
    branch*: string
    worktree*: string
    startTime*: float

  AgentThreadArgs* = tuple[
    repoPath: string,
    assignment: TicketAssignment,
    ticketId: string,
    areaId: string,
    areaContent: string,
    planPath: string,
    nextId: int,
  ]

  TicketPrediction* = object
    difficulty*: string
    durationMinutes*: int
    reasoning*: string

var
  shouldRun* {.volatile.} = true
  ticketStartTimes*: Table[string, float]
  ticketAttemptCounts*: Table[string, int]
  ticketCodingWalls*: Table[string, float]
  ticketTestWalls*: Table[string, float]
  ticketModels*: Table[string, string]
  ticketOutputBytes*: Table[string, int]
  sessionStats*: SessionStats
  timingsLock*: Lock
  timingsLockInitialized* = false
  agentRunnerOverride*: AgentRunner
  forceEvalPending* {.volatile.} = false

proc ensureTimingsLockInitialized*() =
  ## Initialize the timing tables lock once.
  if not timingsLockInitialized:
    initLock(timingsLock)
    timingsLockInitialized = true

proc cleanupTicketTimings*(ticketId: string) =
  ## Remove all per-ticket timing and metrics state for a completed ticket.
  ticketStartTimes.del(ticketId)
  ticketAttemptCounts.del(ticketId)
  ticketCodingWalls.del(ticketId)
  ticketTestWalls.del(ticketId)
  ticketModels.del(ticketId)
  ticketOutputBytes.del(ticketId)

proc isOutputBudgetExceeded*(outputBudgetMB: int): bool =
  ## Check the transcript byte budget, with zero meaning unlimited.
  if outputBudgetMB <= 0:
    return false
  let budgetBytes = outputBudgetMB * 1024 * 1024
  let usedBytes = getSessionOutputBytes()
  if usedBytes >= budgetBytes:
    let usedMB = usedBytes div (1024 * 1024)
    logInfo(&"resource limit: output budget exhausted ({usedMB}MB/{outputBudgetMB}MB), pausing new assignments")
    return true
  return false

proc resetSessionStats*() =
  ## Reset session statistics to default values.
  sessionStats = SessionStats(startTime: epochTime())
  resetOutputUsage()
