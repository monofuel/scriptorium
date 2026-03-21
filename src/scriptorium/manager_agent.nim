import
  std/[os, strformat, strutils, tables],
  ./[agent_pool, agent_runner, architect_agent, config, git_ops, lock_management, logging, prompt_builders, shared_state, ticket_metadata]

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

proc parseTicketDocumentsFromOutput*(output: string): seq[string] =
  ## Parse ticket markdown documents from agent output fenced blocks.
  ## Extracts content between ```markdown and ``` fences.
  var i = 0
  let lines = output.splitLines()
  while i < lines.len:
    let line = lines[i].strip()
    if line.startsWith("```") and "markdown" in line.toLowerAscii():
      inc i
      var docLines: seq[string]
      while i < lines.len:
        if lines[i].strip() == "```":
          inc i
          break
        docLines.add(lines[i])
        inc i
      let content = docLines.join("\n").strip()
      if content.len > 0:
        result.add(content)
    else:
      inc i

proc executeManagerForArea*(areaId: string, areaContent: string, repoPath: string,
    planPath: string, nextId: int, runner: AgentRunner): seq[string] =
  ## Run the manager agent for a single area and return ticket documents in memory.
  let cfg = loadConfig(repoPath)
  let areaRelPath = PlanAreasDir / areaId & ".md"
  let prompt = buildManagerTicketsPrompt(repoPath, planPath, areaId, areaRelPath, areaContent, nextId)
  let agentResult = runner(AgentRunRequest(
    prompt: prompt,
    workingDir: planPath,
    harness: cfg.agents.manager.harness,
    model: resolveModel(cfg.agents.manager.model),
    reasoningEffort: cfg.agents.manager.reasoningEffort,
    ticketId: ManagerTicketIdPrefix & areaId,
    attempt: DefaultAgentAttempt,
    skipGitRepoCheck: true,
    logRoot: planAgentLogRoot(repoPath, ManagerLogDirName / areaId),
    maxAttempts: DefaultAgentMaxAttempts,
    onEvent: proc(event: AgentStreamEvent) =
      if event.kind == agentEventTool:
        logDebug(&"manager[{areaId}]: {event.text}"),
  ))

  # Parse ticket documents from agent output.
  let output = agentResult.stdout & "\n" & agentResult.lastMessage
  result = parseTicketDocumentsFromOutput(output)

  # Fallback: scan for any new ticket files the agent may have written directly.
  if result.len == 0:
    let ticketsDir = planPath / PlanTicketsOpenDir
    if dirExists(ticketsDir):
      for ticketPath in listMarkdownFiles(ticketsDir):
        let content = readFile(planPath / ticketPath).strip()
        if content.len > 0:
          result.add(content)

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

proc syncTicketsFromAreas*(repoPath: string, generateTickets: ManagerTicketGenerator): bool =
  ## Generate and persist tickets for areas without active work.
  if generateTickets.isNil:
    raise newException(ValueError, "manager ticket generator is required")

  let cfg = loadConfig(repoPath)
  result = withLockedPlanWorktree(repoPath, proc(planPath: string): bool =
    let areasToProcess = areasNeedingTicketsInPlanPath(planPath)
    if areasToProcess.len == 0:
      false
    else:
      var nextId = nextTicketId(planPath)
      var hasChanges = false
      for areaRelPath in areasToProcess:
        let areaContent = readFile(planPath / areaRelPath)
        let docs = generateTickets(cfg.agents.manager.model, areaRelPath, areaContent)
        if writeTicketsForArea(planPath, areaRelPath, docs, nextId):
          hasChanges = true

      if hasChanges:
        gitRun(planPath, "add", PlanTicketsOpenDir)
        if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
          gitRun(planPath, "commit", "-m", TicketCommitMessage)

      # Update area hashes after ticket generation
      let currentHashes = computeAllAreaHashes(planPath)
      writeAreaHashes(planPath, currentHashes)
      gitRun(planPath, "add", AreaHashesPath)
      if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
        gitRun(planPath, "commit", "-m", AreaHashesCommitMessage)

      hasChanges
  )

proc runManagerTickets*(repoPath: string, runner: AgentRunner = runAgent): bool =
  ## Run a single batched manager pass that writes ticket files for all areas.
  if runner.isNil:
    raise newException(ValueError, "agent runner is required")

  let cfg = loadConfig(repoPath)
  let repoDirtyStateBefore = snapshotDirtyStateInGitPath(repoPath)
  result = withLockedPlanWorktree(repoPath, proc(planPath: string): bool =
    if not hasRunnableSpecInPlanPath(planPath):
      false
    else:
      let areasToProcess = areasNeedingTicketsInPlanPath(planPath)
      if areasToProcess.len == 0:
        false
      else:
        var areas: seq[tuple[relPath: string, content: string]]
        for areaRelPath in areasToProcess:
          areas.add((relPath: areaRelPath, content: readFile(planPath / areaRelPath)))
        let nextId = nextTicketId(planPath)
        discard runner(AgentRunRequest(
          prompt: buildManagerTicketsBatchPrompt(repoPath, planPath, areas, nextId),
          workingDir: planPath,
          harness: cfg.agents.manager.harness,
          model: resolveModel(cfg.agents.manager.model),
          reasoningEffort: cfg.agents.manager.reasoningEffort,
          ticketId: ManagerTicketIdPrefix & "batch",
          attempt: DefaultAgentAttempt,
          skipGitRepoCheck: true,
          logRoot: planAgentLogRoot(repoPath, ManagerLogDirName / "batch"),
          maxAttempts: DefaultAgentMaxAttempts,
          onEvent: proc(event: AgentStreamEvent) =
            if event.kind == agentEventTool:
              logDebug(fmt"manager[batch]: {event.text}"),
        ))
        enforceWritePrefixAllowlist(planPath, [PlanTicketsOpenDir, PlanTicketsDoneDir], ManagerWriteScopeName)
        enforceGitPathUnchanged(repoPath, repoDirtyStateBefore, ManagerWriteScopeName)

        gitRun(planPath, "add", PlanTicketsOpenDir)
        gitRun(planPath, "add", PlanTicketsDoneDir)
        if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
          gitRun(planPath, "commit", "-m", TicketCommitMessage)

        # Update area hashes after ticket generation
        let currentHashes = computeAllAreaHashes(planPath)
        writeAreaHashes(planPath, currentHashes)
        gitRun(planPath, "add", AreaHashesPath)
        if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
          gitRun(planPath, "commit", "-m", AreaHashesCommitMessage)

        true
  )

proc managerAgentWorkerThread*(args: AgentThreadArgs) {.thread.} =
  ## Run executeManagerForArea in a background thread and send the result to the pool channel.
  {.cast(gcsafe).}:
    let runner: AgentRunner = if not agentRunnerOverride.isNil: agentRunnerOverride else: runAgent
    let ticketDocs = executeManagerForArea(args.areaId, args.areaContent, args.repoPath, args.planPath, args.nextId, runner)
    sendPoolResult(AgentPoolCompletionResult(
      role: arManager,
      ticketId: args.ticketId,
      areaId: args.areaId,
      result: AgentRunResult(),
      managerResult: ticketDocs,
    ))
