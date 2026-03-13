import
  std/[locks, math, strformat, tables, times],
  ./[agent_runner, logging]

const
  SubmitPrSummaryMaxBytes* = 4096
  ActiveWorktreePathMaxBytes* = 1024
  ActiveTicketIdMaxBytes* = 256
  ReviewActionMaxBytes* = 32
  ReviewFeedbackMaxBytes* = 4096
  RateLimitBaseBackoffSeconds* = 2.0
  RateLimitMaxBackoffSeconds* = 120.0
  RateLimitBackoffMultiplier* = 2.0
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

  ManagerTicketGenerator* = proc(model: string, areaPath: string, areaContent: string): seq[TicketDocument]

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

  OrchestratorStatus* = object
    openTickets*: int
    inProgressTickets*: int
    doneTickets*: int
    activeTicketPath*: string
    activeTicketId*: string
    activeTicketBranch*: string
    activeTicketWorktree*: string

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

  AgentSlot* = object
    ticketId*: string
    branch*: string
    worktree*: string
    startTime*: float

  TicketPrediction* = object
    difficulty*: string
    durationMinutes*: int
    reasoning*: string

var
  shouldRun* {.volatile.} = true
  submitPrLock*: Lock
  submitPrLockInitialized* = false
  submitPrSummaries*: Table[string, string]
  activeTicketEntries*: Table[string, string]
  reviewActionLen* = 0
  reviewActionBuffer*: array[ReviewActionMaxBytes, char]
  reviewFeedbackLen* = 0
  reviewFeedbackBuffer*: array[ReviewFeedbackMaxBytes, char]
  ticketStartTimes*: Table[string, float]
  ticketAttemptCounts*: Table[string, int]
  ticketCodingWalls*: Table[string, float]
  ticketTestWalls*: Table[string, float]
  ticketModels*: Table[string, string]
  ticketStdoutBytes*: Table[string, int]
  sessionStats*: SessionStats
  timingsLock*: Lock
  timingsLockInitialized* = false
  agentRunnerOverride*: AgentRunner
  rateLimitBackoffUntil*: float = 0.0
  rateLimitConsecutiveCount*: int = 0
  rateLimitConcurrencyReduction*: int = 0

proc ensureSubmitPrLockInitialized*() {.gcsafe.} =
  ## Initialize the shared submit_pr lock once.
  if not submitPrLockInitialized:
    initLock(submitPrLock)
    submitPrLockInitialized = true

proc ensureTimingsLockInitialized*() =
  ## Initialize the timing tables lock once.
  if not timingsLockInitialized:
    initLock(timingsLock)
    timingsLockInitialized = true

proc recordSubmitPrSummary*(summary: string, ticketId: string = "") {.gcsafe.} =
  ## Store the submit_pr summary for a specific ticket or the sole active ticket.
  ensureSubmitPrLockInitialized()
  {.cast(gcsafe).}:
    withLock submitPrLock:
      var id = ticketId
      if id.len == 0 and activeTicketEntries.len > 0:
        for k in activeTicketEntries.keys:
          id = k
          break
      submitPrSummaries[id] = summary

proc consumeSubmitPrSummary*(ticketId: string = ""): string {.gcsafe.} =
  ## Return and clear the submit_pr summary for a ticket or the first available.
  ensureSubmitPrLockInitialized()
  {.cast(gcsafe).}:
    withLock submitPrLock:
      if ticketId.len > 0:
        if submitPrSummaries.hasKey(ticketId):
          result = submitPrSummaries[ticketId]
          submitPrSummaries.del(ticketId)
      else:
        for k, v in submitPrSummaries:
          result = v
          submitPrSummaries.del(k)
          break

proc setActiveTicketWorktree*(worktreePath: string, ticketId: string) {.gcsafe.} =
  ## Register an active ticket worktree mapping.
  ensureSubmitPrLockInitialized()
  {.cast(gcsafe).}:
    withLock submitPrLock:
      activeTicketEntries[ticketId] = worktreePath

proc clearActiveTicketWorktree*(ticketId: string = "") {.gcsafe.} =
  ## Clear one or all active ticket worktree mappings.
  ensureSubmitPrLockInitialized()
  {.cast(gcsafe).}:
    withLock submitPrLock:
      if ticketId.len > 0:
        activeTicketEntries.del(ticketId)
      else:
        activeTicketEntries.clear()

proc getActiveTicketWorktree*(ticketId: string = ""): tuple[worktreePath: string, ticketId: string] {.gcsafe.} =
  ## Return the active worktree for a ticket or the first available entry.
  ensureSubmitPrLockInitialized()
  {.cast(gcsafe).}:
    withLock submitPrLock:
      if ticketId.len > 0:
        if activeTicketEntries.hasKey(ticketId):
          result = (worktreePath: activeTicketEntries[ticketId], ticketId: ticketId)
      elif activeTicketEntries.len > 0:
        for k, v in activeTicketEntries:
          result = (worktreePath: v, ticketId: k)
          break

proc recordReviewDecision*(action: string, feedback: string) {.gcsafe.} =
  ## Store the latest review decision reported by the review agent.
  ensureSubmitPrLockInitialized()
  withLock submitPrLock:
    let actionLen = min(action.len, ReviewActionMaxBytes)
    reviewActionLen = actionLen
    if actionLen > 0:
      copyMem(addr reviewActionBuffer[0], unsafeAddr action[0], actionLen)
    let fbLen = min(feedback.len, ReviewFeedbackMaxBytes)
    reviewFeedbackLen = fbLen
    if fbLen > 0:
      copyMem(addr reviewFeedbackBuffer[0], unsafeAddr feedback[0], fbLen)

proc consumeReviewDecision*(): tuple[action: string, feedback: string] {.gcsafe.} =
  ## Return and clear the latest review decision reported by the review agent.
  ensureSubmitPrLockInitialized()
  withLock submitPrLock:
    if reviewActionLen > 0:
      result.action = newString(reviewActionLen)
      copyMem(addr result.action[0], addr reviewActionBuffer[0], reviewActionLen)
    if reviewFeedbackLen > 0:
      result.feedback = newString(reviewFeedbackLen)
      copyMem(addr result.feedback[0], addr reviewFeedbackBuffer[0], reviewFeedbackLen)
    reviewActionLen = 0
    reviewFeedbackLen = 0

proc cleanupTicketTimings*(ticketId: string) =
  ## Remove all per-ticket timing and metrics state for a completed ticket.
  ticketStartTimes.del(ticketId)
  ticketAttemptCounts.del(ticketId)
  ticketCodingWalls.del(ticketId)
  ticketTestWalls.del(ticketId)
  ticketModels.del(ticketId)
  ticketStdoutBytes.del(ticketId)

proc getSessionStdoutBytes*(): int =
  ## Sum all ticketStdoutBytes values to get the session-level total.
  for bytes in ticketStdoutBytes.values:
    result += bytes

proc isTokenBudgetExceeded*(tokenBudgetMB: int): bool =
  ## Check if cumulative stdout bytes exceed the token budget. Returns false when budget is 0 (unlimited).
  if tokenBudgetMB <= 0:
    return false
  let budgetBytes = tokenBudgetMB * 1024 * 1024
  let usedBytes = getSessionStdoutBytes()
  if usedBytes >= budgetBytes:
    let usedMB = usedBytes div (1024 * 1024)
    logInfo(&"resource limit: token budget exhausted ({usedMB}MB/{tokenBudgetMB}MB), pausing new assignments")
    return true
  return false

proc isRateLimited*(output: string): bool =
  ## Check if agent output contains rate limit indicators (HTTP 429 or equivalent).
  let lower = output.toLowerAscii()
  if "429" in lower and ("rate" in lower or "too many" in lower or "limit" in lower):
    return true
  if "rate limit" in lower or "rate_limit" in lower or "ratelimit" in lower:
    return true
  if "too many requests" in lower:
    return true
  return false

proc rateLimitBackoffSeconds*(): float =
  ## Calculate the current exponential backoff duration based on consecutive rate limit count.
  if rateLimitConsecutiveCount <= 0:
    return 0.0
  let exponent = rateLimitConsecutiveCount - 1
  let backoff = RateLimitBaseBackoffSeconds * pow(RateLimitBackoffMultiplier, exponent.float)
  result = min(backoff, RateLimitMaxBackoffSeconds)

proc recordRateLimit*(ticketId: string) =
  ## Record a rate limit event: increment counter, set backoff expiry, reduce concurrency by 1.
  rateLimitConsecutiveCount += 1
  let backoffSecs = rateLimitBackoffSeconds()
  rateLimitBackoffUntil = epochTime() + backoffSecs
  rateLimitConcurrencyReduction = rateLimitConsecutiveCount
  let backoffInt = int(backoffSecs)
  logInfo(&"resource limit: rate limited (ticket {ticketId}, backing off {backoffInt}s)")

proc isRateLimitBackoffActive*(): bool =
  ## Check if rate limit backoff is currently active. Restores concurrency when backoff expires.
  if rateLimitBackoffUntil <= 0.0:
    return false
  if epochTime() >= rateLimitBackoffUntil:
    rateLimitBackoffUntil = 0.0
    rateLimitConsecutiveCount = 0
    rateLimitConcurrencyReduction = 0
    return false
  return true

proc effectiveMaxAgents*(maxAgents: int): int =
  ## Return the effective max agents after applying rate limit concurrency reduction.
  result = max(1, maxAgents - rateLimitConcurrencyReduction)

proc resetRateLimitState*() =
  ## Reset all rate limit backpressure state.
  rateLimitBackoffUntil = 0.0
  rateLimitConsecutiveCount = 0
  rateLimitConcurrencyReduction = 0

proc resetSessionStats*() =
  ## Reset session statistics to default values.
  sessionStats = SessionStats(startTime: epochTime())
