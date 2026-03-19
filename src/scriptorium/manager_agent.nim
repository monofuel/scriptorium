import
  std/[os, strformat, strutils, tables],
  ./[agent_runner, architect_agent, config, git_ops, lock_management, logging, prompt_builders, shared_state, ticket_metadata]

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
          logRoot: planAgentLogRoot(ManagerLogDirName / "batch"),
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
