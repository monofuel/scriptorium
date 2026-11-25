import
  std/[os, strformat, strutils, tables],
  ./[agent_pool, agent_runner, architect_agent, config, continuation_builder, git_ops, lock_management, log_forwarding, logging, mcp_server, prompt_builders, shared_state, ticket_metadata]

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
  createDir(planPath / PlanTicketsOpenDir)

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

  let mcpSession = newManagerMcpSession(cfg.endpoints.local, areaId)
  block:
    defer: unregisterAgentMcpSession(mcpSession)
    let response = runner(AgentRunRequest(
      activityRole: "manager",
      activityTask: "Plan tickets: " & parseTitleFromTicketContent(areaContent),
      activityAreaId: areaId,
      activityWorkPath: relativePath(managedPlanWorktreePath(repoPath) / areaRelPath, repoPath),
      prompt: prompt,
      workingDir: repoPath,
      harness: cfg.agents.manager.harness,
      acpAgent: cfg.agents.manager.acpAgent,
      profile: cfg.resolveAcpProfile(cfg.agents.manager),
      configOptions: cfg.agents.manager.configOptions,
      sessionRoot: repoPath / ".scriptorium" / "sessions",
      model: cfg.agents.manager.model,
      reasoningEffort: cfg.agents.manager.reasoningEffort,
      mcpEndpoint: mcpSession.endpoint,
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
    response.requireAgentCompleted()
  let submission = managerSubmission(mcpSession)
  if not submission.called:
    raise newException(ValueError, "Manager ended without submit_tickets: " & areaId)
  result = submission.tickets

proc relocateManagerTickets*(ticketDocs: seq[string], requestedNextId, assignedNextId: int): seq[string] =
  ## Rebase manager-local IDs and dependencies while preserving references to pre-existing tickets.
  if requestedNextId < 1 or assignedNextId < 1:
    raise newException(ValueError, "Manager ticket ID bases must be positive")
  var documents: seq[string]
  for doc in ticketDocs:
    if doc.strip().len > 0: documents.add(doc)
  for index, doc in documents:
    let
      localId = requestedNextId + index
      assignedId = assignedNextId + index
      localLabel = &"{localId:04d}"
      assignedLabel = &"{assignedId:04d}"
    var lines = doc.splitLines()
    for line in lines.mitems:
      if line.startsWith("# " & localLabel) and
          (line.len == 2 + localLabel.len or line[2 + localLabel.len] in {' ', '-'}):
        line = "# " & assignedLabel & line[2 + localLabel.len .. ^1]
      if line.strip().startsWith(DependsFieldPrefix):
        var dependencies: seq[string]
        for dependency in parseDependsFromTicketContent(line):
          let number = parseInt(dependency)
          if number == localId:
            raise newException(ValueError, "Manager ticket depends on itself: " & dependency)
          if number >= requestedNextId:
            if number >= requestedNextId + documents.len:
              raise newException(ValueError, "Manager referenced an unknown provisional ticket: " & dependency)
            let translated = assignedNextId + number - requestedNextId
            dependencies.add(&"{translated:04d}")
          else:
            dependencies.add(dependency)
        if dependencies.len > 0: line = DependsFieldPrefix & " " & dependencies.join(", ")
    result.add(lines.join("\n"))

proc writeTicketsForAreaFromStrings*(planPath: string, areaId: string,
    ticketDocs: seq[string], nextId: int, requestedNextId = 0) =
  ## Write ticket document strings for one area into tickets/open/.
  var currentId = nextId
  createDir(planPath / PlanTicketsOpenDir)
  let documents = if requestedNextId > 0: relocateManagerTickets(ticketDocs, requestedNextId, nextId)
    else: ticketDocs
  for doc in documents:
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

proc runManagerForAreas*(repoPath: string, runner: AgentRunner = runAgent): bool =
  ## Persist each completed serial manager before assigning the next manager's provisional IDs.
  type AreaSnapshot = object
    areaId: string
    content: string
  var areas: seq[AreaSnapshot]
  discard withPlanWorktree(repoPath, proc(planPath: string): bool =
    ## Snapshot the actual area content without holding a Git lock during model calls.
    if not hasRunnableSpecInPlanPath(planPath): return false
    for areaRelPath in areasNeedingTicketsInPlanPath(planPath):
      areas.add(AreaSnapshot(areaId: areaIdFromAreaPath(areaRelPath),
        content: readFile(planPath / areaRelPath)))
    true)
  for area in areas:
    let
      areaId = area.areaId
      areaContent = area.content
    let requestedNextId = withPlanWorktree(repoPath, proc(planPath: string): int =
      ## Include tickets persisted by earlier managers in this same serial batch.
      nextTicketId(planPath))
    let documents = executeManagerForArea(areaId, areaContent, repoPath, requestedNextId, runner)
    discard withLockedPlanWorktree(repoPath, proc(planPath: string): bool =
      ## Resolve any allocation race and record only the area this manager actually planned.
      if documents.len > 0:
        writeTicketsForAreaFromStrings(planPath, areaId, documents, nextTicketId(planPath), requestedNextId)
        gitRun(planPath, "add", PlanTicketsOpenDir)
        if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
          gitRun(planPath, "commit", "-m", "scriptorium: create tickets for " & areaId)
      var hashes = readAreaHashes(planPath)
      hashes[areaId] = computeContentHash(areaContent)
      writeAreaHashes(planPath, hashes)
      gitRun(planPath, "add", AreaHashesPath)
      if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
        gitRun(planPath, "commit", "-m", AreaHashesCommitMessage)
      true)
    if documents.len > 0: result = true

proc managerAgentWorkerThread*(args: AgentThreadArgs) {.thread.} =
  ## Run executeManagerForArea in a background thread and send the result to the pool channel.
  {.cast(gcsafe).}:
    let runner: AgentRunner = if not agentRunnerOverride.isNil: agentRunnerOverride else: runAgent
    var completion = AgentPoolCompletionResult(
      role: arManager,
      ticketId: args.ticketId,
      areaId: args.areaId,
      result: AgentRunResult(),
      managerNextId: args.nextId,
      managerAreaHash: computeContentHash(args.areaContent),
    )
    try:
      completion.managerResult = executeManagerForArea(args.areaId, args.areaContent,
        args.repoPath, args.nextId, runner)
    except CatchableError as error:
      completion.result = AgentRunResult(exitCode: 1, failureKind: failureProtocol,
        errorMessage: error.msg)
    sendPoolResult(completion)

proc launchManagerAreasAsync*(repoPath: string, maxAgents: int) =
  ## Launch per-area manager agents asynchronously for parallel execution.
  discard withPlanWorktree(repoPath, proc(planPath: string): int =
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
