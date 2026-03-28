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
  ChatMode* = enum
    chatModePlan, chatModeAsk, chatModeDo

  ChatThreadArgs = tuple[repoPath: string, token: string, channelId: string, messageText: string, mode: ChatMode]

proc parseChatMode*(message: string): tuple[mode: ChatMode, text: string] =
  ## Parse an optional mode prefix from a Discord message.
  ## Supported prefixes: "ask:", "plan:", "do:". Default: chatModePlan.
  let trimmed = message.strip()
  let lower = trimmed.toLowerAscii()
  if lower.startsWith("ask:"):
    result = (chatModeAsk, trimmed[4..^1].strip())
  elif lower.startsWith("plan:"):
    result = (chatModePlan, trimmed[5..^1].strip())
  elif lower.startsWith("do:"):
    result = (chatModeDo, trimmed[3..^1].strip())
  else:
    result = (chatModePlan, trimmed)

proc truncateMessage(msg: string): string =
  ## Truncate a message to fit within the Discord message character limit.
  if msg.len <= DiscordMessageLimit:
    result = msg
  else:
    let markerLen = TruncatedMarker.len
    result = msg[0 ..< DiscordMessageLimit - markerLen] & TruncatedMarker

proc registerSlashCommands(c: GuildyClient, serverId: string) =
  ## Register slash commands with Discord after gateway READY.
  ## When serverId is set, registers as guild commands (instant). Otherwise global (slow propagation).
  let commands = @[
    SlashCommand(name: "status", description: "Show orchestrator status and ticket counts", `type`: 1),
    SlashCommand(name: "queue", description: "Show merge queue and ticket lists", `type`: 1),
    SlashCommand(name: "pause", description: "Pause the orchestrator", `type`: 1),
    SlashCommand(name: "resume", description: "Resume the orchestrator", `type`: 1),
  ]
  discard c.registerCommands(toJson(commands), serverId)
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

proc handleAskMessage(repoPath: string, client: GuildyClient, channelId: string, messageText: string) =
  ## Invoke the architect in read-only mode and post the response to the channel.
  let cfg = loadConfig(repoPath)
  var response = ""
  try:
    response = withLockedPlanWorktree(repoPath, proc(planPath: string): string =
      let spec = loadSpecFromPlanPath(planPath)
      let prompt = buildInteractiveAskPrompt(repoPath, planPath, spec, @[], messageText)
      let agentResult = runPlanArchitectRequest(
        runAgent,
        repoPath,
        planPath,
        cfg.agents.architect,
        prompt,
        DiscordChatTicketId,
      )
      enforceNoWrites(planPath, "scriptorium discord ask")

      var reply = agentResult.lastMessage.strip()
      if reply.len == 0:
        reply = agentResult.stdout.strip()
      if reply.len == 0:
        reply = "(no response from architect)"
      reply
    )
  except CatchableError as e:
    let errMsg = e.msg
    echo &"scriptorium: discord ask error: {errMsg}"
    response = &"Error: {errMsg}"

  discard client.postChannelMessage(channelId, response)

proc handleDoMessage(repoPath: string, client: GuildyClient, channelId: string, messageText: string) =
  ## Invoke the architect with full repo access and post the response to the channel.
  {.cast(gcsafe).}:
    let cfg = loadConfig(repoPath)
    var response = ""
    try:
      let prompt = buildDoOneShotPrompt(repoPath, messageText)
      let agentResult = runDoArchitectRequest(
        runAgent,
        repoPath,
        cfg.agents.architect,
        prompt,
        DiscordChatTicketId,
      )
      response = agentResult.lastMessage.strip()
      if response.len == 0:
        response = agentResult.stdout.strip()
      if response.len == 0:
        response = "(no response from architect)"
    except CatchableError as e:
      let errMsg = e.msg
      echo &"scriptorium: discord do error: {errMsg}"
      response = &"Error: {errMsg}"

    discard client.postChannelMessage(channelId, response)

proc chatWorkerThread(args: ChatThreadArgs) {.thread.} =
  ## Run architect chat in a background thread, routed by mode.
  let restClient = newGuildyClient(args.token)
  case args.mode
  of chatModePlan:
    handleChatMessage(args.repoPath, restClient, args.channelId, args.messageText)
  of chatModeAsk:
    handleAskMessage(args.repoPath, restClient, args.channelId, args.messageText)
  of chatModeDo:
    handleDoMessage(args.repoPath, restClient, args.channelId, args.messageText)

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

  let serverId = cfg.discord.serverId
  let allowedUserIds = cfg.discord.allowedUserIds
  let client = newGuildyClient(token)

  let onRaw = proc(c: GuildyClient, event: JsonNode) {.gcsafe.} =
    if event.hasKey("t") and event["t"].getStr() == "READY":
      registerSlashCommands(c, serverId)

  let onMessage = proc(c: GuildyClient, msg: DiscordMessage) {.gcsafe.} =
    if msg.channel_id != channelId:
      return
    if msg.author.bot:
      return
    if allowedUserIds.len > 0 and msg.author.id notin allowedUserIds:
      return
    let user = msg.author.username
    let content = msg.content
    let (mode, text) = parseChatMode(content)
    echo &"scriptorium: discord message from {user} (mode={mode}): {text}"
    # Spawn background thread to avoid blocking the gateway event loop.
    let threadPtr = create(Thread[ChatThreadArgs])
    createThread(threadPtr[], chatWorkerThread, (repoPath, token, channelId, text, mode))

  let onInteraction = proc(c: GuildyClient, interaction: DiscordInteraction) {.gcsafe.} =
    if interaction.channel_id != channelId:
      return
    if allowedUserIds.len > 0 and interaction.user_id notin allowedUserIds:
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
