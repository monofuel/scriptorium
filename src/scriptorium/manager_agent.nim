import
  std/[os, strformat, strutils, tables],
  ./[agent_pool, agent_runner, architect_agent, config, continuation_builder, git_ops, lock_management, log_forwarding, logging, prompt_builders, shared_state, ticket_metadata]

const
  TicketCommitMessage = "scriptorium: create tickets from areas"
  ManagerWriteScopeName = "scriptorium manager"
  ManagerLogDirName = "manager"
  ManagerTicketIdPrefix = "manager-"

proc nextTicketId*(planPath: string): int =
  ## Compute the next monotonic ticket ID by scanning all ticket states.
  result = 1
  for stateDir in [PlanTicketsOpenDir, PlanTicketsInProgressDir, PlanTicketsDoneDir, PlanTicketsStuckDir]:
    for ticketPath in listMarkdownFiles(planPath / stateDir):
      let ticketName = splitFile(ticketPath).name
      let dashPos = ticketName.find('-')
      if dashPos > 0:
        let prefix = ticketName[0..<dashPos]
        if prefix.allCharsInSet(Digits):
          let parsedId = parseInt(prefix)
          if parsedId >= result:
            result = parsedId + 1

proc writeTicketsForArea*(
  planPath: string,
  areaRelPath: string,
  docs: seq[TicketDocument],
  nextId: var int,
): bool =
  ## Write manager-generated tickets for one area into tickets/open.
  let areaId = areaIdFromAreaPath(areaRelPath)
  var hasChanges = false

  for doc in docs:
    let slug = normalizeTicketSlug(doc.slug)
    let ticketPath = planPath / PlanTicketsOpenDir / fmt"{nextId:04d}-{slug}.md"
    let body = doc.content.strip()
    if body.len == 0:
      raise newException(ValueError, "ticket content cannot be empty")

    let existingArea = parseAreaFromTicketContent(body)
    var ticketContent = body
    if existingArea.len == 0:
      ticketContent &= "\n\n" & AreaFieldPrefix & " " & areaId & "\n"
    elif existingArea != areaId:
      raise newException(ValueError, fmt"ticket area '{existingArea}' does not match area '{areaId}'")
    else:
      ticketContent &= "\n"

    writeFile(ticketPath, ticketContent)
    hasChanges = true
    inc nextId

  result = hasChanges

proc executeManagerForArea*(areaId: string, areaContent: string, repoPath: string,
    nextId: int, runner: AgentRunner): seq[string] =
  ## Run the manager agent for a single area and return ticket documents in memory.
  ## The agent calls the submit_tickets MCP tool to deliver tickets.
  let cfg = loadConfig(repoPath)
  let areaRelPath = PlanAreasDir / areaId & ".md"
  let prompt = buildManagerTicketsPrompt(repoPath, areaId, areaRelPath, areaContent, nextId)

  # Clear any stale tickets from a previous run for this area.
  discard consumeSubmitTickets(areaId)

  discard runner(AgentRunRequest(
    prompt: prompt,
    workingDir: repoPath,
    harness: cfg.agents.manager.harness,
    model: cfg.agents.manager.model,
    reasoningEffort: cfg.agents.manager.reasoningEffort,
    mcpEndpoint: cfg.endpoints.local,
    ticketId: ManagerTicketIdPrefix & areaId,
    attempt: DefaultAgentAttempt,
    skipGitRepoCheck: true,
    logRoot: planAgentLogRoot(repoPath, ManagerLogDirName / areaId),
    noOutputTimeoutMs: cfg.agents.manager.noOutputTimeout,
    hardTimeoutMs: cfg.agents.manager.hardTimeout,
    progressTimeoutMs: cfg.agents.manager.progressTimeout,
    maxAttempts: DefaultAgentMaxAttempts,
    continuationPromptBuilder: buildAgentsReinjectPrompt,
    onEvent: proc(event: AgentStreamEvent) =
      forwardAgentEvent("manager", areaId, event),
  ))

  # Consume tickets submitted via the MCP tool.
  result = consumeSubmitTickets(areaId)

proc writeTicketsForAreaFromStrings*(planPath: string, areaId: string,
    ticketDocs: seq[string], nextId: int) =
  ## Write ticket document strings for one area into tickets/open/.
  var currentId = nextId
  for doc in ticketDocs:
    let body = doc.strip()
    if body.len == 0:
      continue
    # Extract a slug from the first heading line.
    var slug = areaId
    for line in body.splitLines():
      let trimmed = line.strip()
      if trimmed.startsWith("# "):
        slug = normalizeTicketSlug(trimmed[2..^1])
        break
    let ticketPath = planPath / PlanTicketsOpenDir / fmt"{currentId:04d}-{slug}.md"
    let existingArea = parseAreaFromTicketContent(body)
    var ticketContent = body
    if existingArea.len == 0:
      ticketContent &= "\n\n" & AreaFieldPrefix & " " & areaId & "\n"
    elif existingArea != areaId:
      raise newException(ValueError, fmt"ticket area '{existingArea}' does not match area '{areaId}'")
    else:
      ticketContent &= "\n"
    writeFile(ticketPath, ticketContent)
    inc currentId

proc runManagerForAreas*(repoPath: string, caller: string, runner: AgentRunner = runAgent): bool =
  ## Run per-area manager agents serially with narrow plan branch locking.
  ## 1. Brief lock to snapshot area content.
  ## 2. No lock during agent execution.
  ## 3. Brief lock per area to write tickets and commit.
  type AreaSnapshot = object
    areaId: string
    areaRelPath: string
    areaContent: string
    nextId: int

  # Step 1: Brief lock to read area snapshots.
  var areas: seq[AreaSnapshot]
  discard withPlanWorktree(repoPath, caller, proc(planPath: string): bool =
    if not hasRunnableSpecInPlanPath(planPath):
      return false
    let areasToProcess = areasNeedingTicketsInPlanPath(planPath)
    for areaRelPath in areasToProcess:
      let areaId = areaIdFromAreaPath(areaRelPath)
      areas.add(AreaSnapshot(
        areaId: areaId,
        areaRelPath: areaRelPath,
        areaContent: readFile(planPath / areaRelPath),
        nextId: nextTicketId(planPath),
      ))
    false
  )

  if areas.len == 0:
    return false

  # Step 2: Execute managers without holding the lock.
  type AreaResult = object
    areaId: string
    ticketDocs: seq[string]

  var results: seq[AreaResult]
  for area in areas:
    let ticketDocs = executeManagerForArea(area.areaId, area.areaContent, repoPath, area.nextId, runner)
    if ticketDocs.len > 0:
      results.add(AreaResult(areaId: area.areaId, ticketDocs: ticketDocs))

  # Step 3: Brief lock per completed manager to write tickets and commit.
  var hasChanges = false
  for i in 0..<results.len:
    let areaId = results[i].areaId
    let ticketDocs = results[i].ticketDocs
    discard withLockedPlanWorktree(repoPath, caller, proc(planPath: string): bool =
      let nextId = nextTicketId(planPath)
      writeTicketsForAreaFromStrings(planPath, areaId, ticketDocs, nextId)
      gitRun(planPath, "add", PlanTicketsOpenDir)
      if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
        gitRun(planPath, "commit", "-m", "scriptorium: create tickets for " & areaId)
      true
    )
    hasChanges = true

  # Update area hashes after all writes.
  if hasChanges:
    discard withLockedPlanWorktree(repoPath, caller, proc(planPath: string): bool =
      let currentHashes = computeAllAreaHashes(planPath)
      writeAreaHashes(planPath, currentHashes)
      gitRun(planPath, "add", AreaHashesPath)
      if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
        gitRun(planPath, "commit", "-m", AreaHashesCommitMessage)
      true
    )

  result = hasChanges

proc managerAgentWorkerThread*(args: AgentThreadArgs) {.thread.} =
  ## Run executeManagerForArea in a background thread and send the result to the pool channel.
  {.cast(gcsafe).}:
    let runner: AgentRunner = if not agentRunnerOverride.isNil: agentRunnerOverride else: runAgent
    let ticketDocs = executeManagerForArea(args.areaId, args.areaContent, args.repoPath, args.nextId, runner)
    sendPoolResult(AgentPoolCompletionResult(
      role: arManager,
      ticketId: args.ticketId,
      areaId: args.areaId,
      result: AgentRunResult(),
      managerResult: ticketDocs,
    ))

proc launchManagerAreasAsync*(repoPath: string, caller: string, maxAgents: int) =
  ## Launch per-area manager agents asynchronously for parallel execution.
  discard withPlanWorktree(repoPath, caller, proc(planPath: string): int =
    if not hasRunnableSpecInPlanPath(planPath):
      return 0
    let areasToProcess = areasNeedingTicketsInPlanPath(planPath)
    for areaRelPath in areasToProcess:
      let areaId = areaIdFromAreaPath(areaRelPath)
      let areaContent = readFile(planPath / areaRelPath)
      let nextId = nextTicketId(planPath)
      startManagerAgentAsync(repoPath, areaId, areaContent, planPath, nextId, maxAgents, managerAgentWorkerThread)
    0
  )
