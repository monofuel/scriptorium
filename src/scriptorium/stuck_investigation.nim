import
  std/[os, strformat, strutils],
  ./[agent_runner, architect_agent, config, git_ops, journal, lock_management, logging, merge_queue, prompt_builders, shared_state, ticket_metadata]

const
  InvestigationCountMarker* = "## Investigation Count: "
  MaxInvestigationCount* = 1
  InvestigateStuckRunId = "investigate-stuck"
  InvestigateStuckCommitPrefix = "scriptorium: investigate stuck ticket"

type
  StuckTicketInfo = object
    ## Snapshot of a stuck ticket captured under the plan lock.
    filename: string
    ticketId: string
    content: string
    stuckCount: int
    investigationCount: int

proc parseInvestigationCount*(content: string): int =
  ## Parse the investigation count from ticket content. Returns 0 if no marker found.
  for line in content.splitLines():
    if line.startsWith(InvestigationCountMarker):
      let countStr = line[InvestigationCountMarker.len .. ^1].strip()
      try:
        return parseInt(countStr)
      except ValueError:
        return 0
  return 0

proc setInvestigationCount*(content: string, count: int): string =
  ## Set or update the investigation count marker in ticket content.
  let marker = InvestigationCountMarker & $count
  let existing = content.find(InvestigationCountMarker)
  if existing >= 0:
    let lineEnd = content.find('\n', existing)
    if lineEnd >= 0:
      result = content[0 ..< existing] & marker & content[lineEnd .. ^1]
    else:
      result = content[0 ..< existing] & marker
  else:
    result = content.strip() & "\n\n" & marker & "\n"

proc classifyStuckFailure*(ticketContent: string): string =
  ## Classify the root cause of merge queue failures from ticket content.
  ## Scans Merge Queue Failure sections for known error patterns.
  let lower = ticketContent.toLowerAscii()
  if lower.contains("local changes") and lower.contains("would be overwritten"):
    result = "dirty_working_tree"
  elif lower.contains("conflict"):
    result = "merge_conflict"
  elif lower.contains("failed gate:"):
    let failedGateIdx = lower.find("failed gate:")
    let afterGate = lower[failedGateIdx .. ^1]
    if afterGate.contains("make test") or afterGate.contains("make integration-test"):
      result = "test_failure"
    else:
      result = "unknown"
  else:
    result = "unknown"

proc gatherMainRepoContext*(repoPath: string): tuple[gitStatus: string, recentCommits: string] =
  ## Gather git status and recent commits from the main repository working tree.
  let statusResult = runCommandCapture(repoPath, "git", @["status", "--porcelain"])
  let logResult = runCommandCapture(repoPath, "git", @["log", "--oneline", "-5"])
  result.gitStatus = statusResult.output.strip()
  result.recentCommits = logResult.output.strip()

proc investigateStuckTicket*(repoPath: string, runner: AgentRunner, ticketId: string, ticketContent: string): bool =
  ## Run the architect to investigate a stuck ticket and take corrective action.
  ## Must be called outside the plan worktree lock. Returns true if the agent ran.
  let classification = classifyStuckFailure(ticketContent)
  if classification == "test_failure":
    logInfo(&"stuck ticket {ticketId}: skipping investigation (test failure handled by recovery agent)")
    return false

  let ctx = gatherMainRepoContext(repoPath)
  let prompt = buildInvestigateStuckPrompt(repoPath, ticketContent, classification, ctx.gitStatus, ctx.recentCommits)
  let cfg = loadConfig(repoPath)
  logInfo(&"stuck ticket {ticketId}: starting investigation (classification={classification})")
  let agentResult = runDoArchitectRequest(
    runner,
    repoPath,
    cfg.agents.architect,
    prompt,
    InvestigateStuckRunId,
  )
  logInfo(&"stuck ticket {ticketId}: investigation finished (exit={agentResult.exitCode})")
  result = true

proc investigateAndRecoverStuckTickets*(repoPath: string, runner: AgentRunner): int =
  ## Investigate stuck tickets and move recoverable ones back to open.
  ## Replaces the old recoverStuckTickets with architect-driven investigation.
  ## Returns the number of tickets recovered.

  # Phase 1: Snapshot recoverable stuck tickets under a brief lock.
  let tickets = withPlanWorktree(repoPath, proc(planPath: string): seq[StuckTicketInfo] =
    var items: seq[StuckTicketInfo]
    let stuckFiles = listMarkdownFiles(planPath / PlanTicketsStuckDir)
    for ticketPath in stuckFiles:
      let content = readFile(ticketPath)
      let stuckCount = parseStuckCount(content)
      if stuckCount >= MaxStuckCount:
        continue
      let filename = extractFilename(ticketPath)
      let ticketId = ticketIdFromTicketPath(PlanTicketsStuckDir / filename)
      items.add(StuckTicketInfo(
        filename: filename,
        ticketId: ticketId,
        content: content,
        stuckCount: stuckCount,
        investigationCount: parseInvestigationCount(content),
      ))
    items
  )

  if tickets.len == 0:
    return 0

  # Phase 2: Investigate each ticket outside the lock (agent calls may take minutes).
  var investigated: seq[bool]
  for ticket in tickets:
    if ticket.investigationCount < MaxInvestigationCount:
      let ran = investigateStuckTicket(repoPath, runner, ticket.ticketId, ticket.content)
      investigated.add(ran)
    else:
      investigated.add(false)

  # Phase 3: Move tickets from stuck to open under the write lock.
  result = withLockedPlanWorktree(repoPath, proc(planPath: string): int =
    var recovered = 0
    for i, ticket in tickets:
      # Re-read content in case it changed.
      let ticketPath = planPath / PlanTicketsStuckDir / ticket.filename
      if not fileExists(ticketPath):
        continue
      let content = readFile(ticketPath)
      var updatedContent = content
      if investigated[i]:
        let currentCount = parseInvestigationCount(content)
        updatedContent = setInvestigationCount(content, currentCount + 1)

      let openRelPath = PlanTicketsOpenDir / ticket.filename
      let commitMsg = InvestigateStuckCommitPrefix & " " & ticket.ticketId
      let steps = @[
        newWriteStep(PlanTicketsStuckDir / ticket.filename, updatedContent),
        newMoveStep(PlanTicketsStuckDir / ticket.filename, openRelPath),
      ]
      beginJournalTransition(planPath, "unstick " & ticket.ticketId, steps, commitMsg)
      executeJournalSteps(planPath)
      completeJournalTransition(planPath)
      logInfo(&"recovered stuck ticket {ticket.ticketId} (stuck count {ticket.stuckCount}, investigated={investigated[i]})")
      recovered += 1
    recovered
  )
