import
  std/[os, strformat, strutils],
  ./[git_ops, lock_management, merge_queue, pause_flag, shared_state,
     ticket_assignment, ticket_metadata]

const
  TruncatedMarker* = "... [truncated]"

type
  ChatMode* = enum
    chatModePlan, chatModeAsk, chatModeDo, chatModeChat, chatModeIgnore

proc parseChatMode*(message: string): tuple[mode: ChatMode, text: string, explicit: bool] =
  ## Parse an optional mode prefix from a chat message.
  ## Supported prefixes: "ask:", "plan:", "do:". Default: chatModePlan.
  ## Returns explicit=true when a prefix was found, false when defaulting.
  let trimmed = message.strip()
  let lower = trimmed.toLowerAscii()
  if lower.startsWith("ask:"):
    result = (chatModeAsk, trimmed[4..^1].strip(), true)
  elif lower.startsWith("plan:"):
    result = (chatModePlan, trimmed[5..^1].strip(), true)
  elif lower.startsWith("do:"):
    result = (chatModeDo, trimmed[3..^1].strip(), true)
  else:
    result = (chatModePlan, trimmed, false)

proc truncateMessage*(msg: string, limit: int): string =
  ## Truncate a message to fit within the given character limit.
  if msg.len <= limit:
    result = msg
  else:
    let markerLen = TruncatedMarker.len
    result = msg[0 ..< limit - markerLen] & TruncatedMarker

proc formatStatusMessage*(repoPath: string): string =
  ## Build the /status response string from orchestrator state.
  let status = readOrchestratorStatus(repoPath)
  var lines: seq[string] = @[]

  # Orchestrator running check.
  let pidPath = orchestratorPidPath(repoPath)
  let running = fileExists(pidPath)
  let runningStr = if running: "yes" else: "no"
  lines.add("**Orchestrator running:** " & runningStr)

  # Paused check.
  let paused = isPaused(repoPath)
  let pausedStr = if paused: "yes" else: "no"
  lines.add("**Paused:** " & pausedStr)

  # Ticket counts.
  let openCount = $status.openTickets
  let inProgressCount = $status.inProgressTickets
  let doneCount = $status.doneTickets
  let stuckCount = $status.stuckTickets
  lines.add(&"**Tickets:** Open: {openCount} | In-Progress: {inProgressCount} | Done: {doneCount} | Stuck: {stuckCount}")

  # Active agent.
  if status.activeTicketId.len > 0:
    let activeId = status.activeTicketId
    lines.add(&"**Active agent:** {activeId}")
  else:
    lines.add("**Active agent:** none")

  # In-progress elapsed times.
  if status.inProgressElapsed.len > 0:
    lines.add("**In-progress tickets:**")
    for item in status.inProgressElapsed:
      let ticketId = item.ticketId
      let elapsed = item.elapsed
      lines.add(&"  {ticketId}: {elapsed}")

  # Blocked tickets.
  for item in status.blockedTickets:
    let cycleList = item.cycleIds.join(", ")
    let ticketId = item.ticketId
    lines.add(&"**Blocked:** {ticketId} (cycle: {cycleList})")

  # Waiting tickets.
  for item in status.waitingTickets:
    let depList = item.dependsOn.join(", ")
    let ticketId = item.ticketId
    lines.add(&"**Waiting:** {ticketId} (depends on {depList})")

  result = lines.join("\n")

proc formatQueueMessage*(repoPath: string): string =
  ## Build the /queue response string from plan branch state.
  var lines: seq[string] = @[]

  let queueResult = withPlanWorktree(repoPath, proc(planPath: string): string =
    var inner: seq[string] = @[]

    # Merge queue items.
    let queueItems = listMergeQueueItems(planPath)
    let queueCount = $queueItems.len
    inner.add(&"**Merge queue:** {queueCount} item(s)")
    for item in queueItems:
      let ticketId = item.ticketId
      let summary = item.summary
      inner.add(&"  {ticketId}: {summary}")

    # In-progress tickets.
    let inProgressFiles = listMarkdownFiles(planPath / PlanTicketsInProgressDir)
    let inProgressCount = $inProgressFiles.len
    inner.add(&"**In-progress tickets:** {inProgressCount}")
    for path in inProgressFiles:
      let fileName = extractFilename(path)
      let ticketId = fileName.replace(".md", "")
      inner.add(&"  {ticketId}")

    # Open tickets.
    let openFiles = listMarkdownFiles(planPath / PlanTicketsOpenDir)
    let openCount = $openFiles.len
    inner.add(&"**Open tickets:** {openCount}")
    for path in openFiles:
      let fileName = extractFilename(path)
      let ticketId = fileName.replace(".md", "")
      inner.add(&"  {ticketId}")

    result = inner.join("\n")
  )

  lines.add(queueResult)
  result = lines.join("\n")

proc handlePause*(repoPath: string): string =
  ## Handle the /pause command.
  if isPaused(repoPath):
    result = "Orchestrator is already paused."
  else:
    writePauseFlag(repoPath)
    result = "Orchestrator paused. In-flight agents will finish but no new work will start."

proc handleResume*(repoPath: string): string =
  ## Handle the /resume command.
  if not isPaused(repoPath):
    result = "Orchestrator was not paused."
  else:
    removePauseFlag(repoPath)
    result = "Orchestrator resumed. New work will be picked up on the next tick."
