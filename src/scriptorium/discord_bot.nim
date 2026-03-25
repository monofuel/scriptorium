import
  std/[json, os, strformat, strutils],
  guildy,
  jsony,
  ./[agent_runner, architect_agent, config, git_ops, lock_management, merge_queue,
     pause_flag, prompt_builders, shared_state, ticket_assignment, ticket_metadata]

const
  DiscordMessageLimit = 2000
  TruncatedMarker = "... [truncated]"
  SpecUpdatedNote = "\n[spec.md updated]"
  DiscordChatTicketId = "discord-chat"
  InteractionResponseMessage = 4

type
  ChatThreadArgs = tuple[repoPath: string, token: string, channelId: string, messageText: string]

proc truncateMessage(msg: string): string =
  ## Truncate a message to fit within the Discord message character limit.
  if msg.len <= DiscordMessageLimit:
    result = msg
  else:
    let markerLen = TruncatedMarker.len
    result = msg[0 ..< DiscordMessageLimit - markerLen] & TruncatedMarker

proc registerSlashCommands(c: GuildyClient) =
  ## Register slash commands with Discord after gateway READY.
  let commands = @[
    SlashCommand(name: "status", description: "Show orchestrator status and ticket counts", `type`: 1),
    SlashCommand(name: "queue", description: "Show merge queue and ticket lists", `type`: 1),
    SlashCommand(name: "pause", description: "Pause the orchestrator", `type`: 1),
    SlashCommand(name: "resume", description: "Resume the orchestrator", `type`: 1),
  ]
  discard c.registerCommands(toJson(commands))
  echo "scriptorium: registered slash commands"

proc handleChatMessage(repoPath: string, client: GuildyClient, channelId: string, messageText: string) =
  ## Invoke the architect with a chat message and post the response to the channel.
  let cfg = loadConfig(repoPath)
  var specChanged = false
  var response = ""
  try:
    response = withLockedPlanWorktree(repoPath, proc(planPath: string): string =
      let existingSpec = loadSpecFromPlanPath(planPath)
      let prompt = buildArchitectPlanPrompt(repoPath, planPath, messageText, existingSpec)
      let agentResult = runPlanArchitectRequest(
        runAgent,
        repoPath,
        planPath,
        cfg.agents.architect,
        prompt,
        DiscordChatTicketId,
      )
      enforceWriteAllowlist(planPath, [PlanSpecPath], PlanWriteScopeName)

      let updatedSpec = loadSpecFromPlanPath(planPath)
      if updatedSpec != existingSpec:
        gitRun(planPath, "add", PlanSpecPath)
        if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
          gitRun(planPath, "commit", "-m", PlanSpecCommitMessage)
        specChanged = true

      var reply = agentResult.lastMessage.strip()
      if reply.len == 0:
        reply = agentResult.stdout.strip()
      if reply.len == 0:
        reply = "(no response from architect)"
      reply
    )
  except CatchableError as e:
    let errMsg = e.msg
    echo &"scriptorium: discord architect error: {errMsg}"
    response = &"Error: {errMsg}"

  if specChanged:
    response = response & SpecUpdatedNote
  discard client.postChannelMessage(channelId, response)

proc chatWorkerThread(args: ChatThreadArgs) {.thread.} =
  ## Run architect chat in a background thread to avoid blocking the gateway.
  let restClient = newGuildyClient(args.token)
  handleChatMessage(args.repoPath, restClient, args.channelId, args.messageText)

proc formatStatusMessage(repoPath: string): string =
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

proc formatQueueMessage(repoPath: string): string =
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

proc handlePause(repoPath: string): string =
  ## Handle the /pause slash command.
  if isPaused(repoPath):
    result = "Orchestrator is already paused."
  else:
    writePauseFlag(repoPath)
    result = "Orchestrator paused. In-flight agents will finish but no new work will start."

proc handleResume(repoPath: string): string =
  ## Handle the /resume slash command.
  if not isPaused(repoPath):
    result = "Orchestrator was not paused."
  else:
    removePauseFlag(repoPath)
    result = "Orchestrator resumed. New work will be picked up on the next tick."

proc runDiscordBot*(repoPath: string) =
  ## Start the Discord bot gateway connection.
  let token = getEnv("DISCORD_TOKEN")
  if token.len == 0:
    echo "scriptorium: DISCORD_TOKEN environment variable is required"
    quit(1)

  let cfg = loadConfig(repoPath)
  let channelId = cfg.discord.channelId
  if channelId.len == 0:
    echo "scriptorium: discord.channelId is required in scriptorium.json"
    quit(1)

  let allowedUsers = cfg.discord.allowedUsers
  let client = newGuildyClient(token)

  let onRaw = proc(c: GuildyClient, event: JsonNode) {.gcsafe.} =
    if event.hasKey("t") and event["t"].getStr() == "READY":
      registerSlashCommands(c)

  let onMessage = proc(c: GuildyClient, msg: DiscordMessage) {.gcsafe.} =
    if msg.channel_id != channelId:
      return
    if msg.author.bot:
      return
    if allowedUsers.len > 0 and msg.author.id notin allowedUsers:
      return
    let user = msg.author.username
    let content = msg.content
    echo &"scriptorium: discord message from {user}: {content}"
    # Spawn background thread to avoid blocking the gateway event loop.
    let threadPtr = create(Thread[ChatThreadArgs])
    createThread(threadPtr[], chatWorkerThread, (repoPath, token, channelId, content))

  let onInteraction = proc(c: GuildyClient, interaction: DiscordInteraction) {.gcsafe.} =
    if interaction.channel_id != channelId:
      return
    if allowedUsers.len > 0 and interaction.user_id notin allowedUsers:
      return
    let cmd = interaction.command_name
    echo &"scriptorium: slash command /{cmd}"
    var response = ""
    case cmd
    of "status":
      response = formatStatusMessage(repoPath)
    of "queue":
      response = formatQueueMessage(repoPath)
    of "pause":
      response = handlePause(repoPath)
    of "resume":
      response = handleResume(repoPath)
    else:
      response = "Unknown command."
    let truncated = truncateMessage(response)
    c.respondToInteraction(interaction.id, interaction.token, InteractionResponseMessage, truncated)

  echo "scriptorium: starting Discord bot"
  client.startGateway(onRaw = onRaw, onMessage = onMessage, onInteraction = onInteraction)
