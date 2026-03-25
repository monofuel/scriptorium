import
  std/[httpclient, json, os, strformat, strutils],
  guildy,
  ./[agent_runner, architect_agent, config, git_ops, lock_management, merge_queue,
     pause_flag, prompt_builders, shared_state, ticket_assignment, ticket_metadata]

const
  DiscordApiBase = "https://discord.com/api/v10"
  DiscordMessageLimit = 2000
  ApplicationCommandType = 1
  TruncatedMarker = "... [truncated]"
  SpecUpdatedNote = "\n[spec.md updated]"
  DiscordChatTicketId = "discord-chat"

proc truncateMessage(msg: string): string =
  ## Truncate a message to fit within the Discord message character limit.
  if msg.len <= DiscordMessageLimit:
    result = msg
  else:
    let markerLen = TruncatedMarker.len
    result = msg[0 ..< DiscordMessageLimit - markerLen] & TruncatedMarker

proc registerSlashCommands(token: string) =
  ## Register slash commands as global application commands.
  let client = newHttpClient()
  client.headers = newHttpHeaders({
    "Authorization": "Bot " & token,
    "Content-Type": "application/json",
  })
  # Fetch the bot's application ID.
  let meResp = client.getContent(DiscordApiBase & "/users/@me")
  let appId = parseJson(meResp)["id"].getStr()

  # Bulk overwrite global application commands.
  let commands = %*[
    {"name": "status", "type": ApplicationCommandType, "description": "Show orchestrator status and ticket counts"},
    {"name": "queue", "type": ApplicationCommandType, "description": "Show merge queue and ticket lists"},
    {"name": "pause", "type": ApplicationCommandType, "description": "Pause the orchestrator"},
    {"name": "resume", "type": ApplicationCommandType, "description": "Resume the orchestrator"},
  ]
  let url = DiscordApiBase & "/applications/" & appId & "/commands"
  discard client.putContent(url, $commands)
  client.close()
  echo "scriptorium: registered slash commands"

proc respondToInteraction(token: string, interactionId: string, interactionToken: string, content: string) =
  ## Send an interaction response to Discord.
  let client = newHttpClient()
  client.headers = newHttpHeaders({
    "Authorization": "Bot " & token,
    "Content-Type": "application/json",
  })
  let body = %*{
    "type": 4,
    "data": {"content": truncateMessage(content)},
  }
  let url = DiscordApiBase & "/interactions/" & interactionId & "/" & interactionToken & "/callback"
  discard client.postContent(url, $body)
  client.close()

proc sendChannelMessage(token: string, channelId: string, content: string) =
  ## Post a message to a Discord channel.
  let client = newHttpClient()
  client.headers = newHttpHeaders({
    "Authorization": "Bot " & token,
    "Content-Type": "application/json",
  })
  let body = %*{"content": truncateMessage(content)}
  let url = DiscordApiBase & "/channels/" & channelId & "/messages"
  discard client.postContent(url, $body)
  client.close()

proc handleChatMessage(repoPath: string, token: string, channelId: string, messageText: string) =
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
  sendChannelMessage(token, channelId, response)

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

  registerSlashCommands(token)

  let bot = newDiscordBot(token)

  bot.onMessage = proc(msg: DiscordMessage) {.gcsafe.} =
    if msg.channelId != channelId:
      return
    if msg.author.bot:
      return
    if allowedUsers.len > 0 and msg.author.id notin allowedUsers:
      return
    let user = msg.author.username
    let content = msg.content
    echo &"scriptorium: discord message from {user}: {content}"
    handleChatMessage(repoPath, token, channelId, content)

  bot.onInteraction = proc(interaction: DiscordInteraction) {.gcsafe.} =
    # Scope to configured channel.
    if interaction.channelId != channelId:
      return
    # Enforce allowed users.
    if allowedUsers.len > 0 and interaction.userId notin allowedUsers:
      return
    let cmd = interaction.commandName
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
    respondToInteraction(token, interaction.id, interaction.token, response)

  echo "scriptorium: starting Discord bot"
  bot.run()
