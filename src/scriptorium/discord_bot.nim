import
  std/[algorithm, json, locks, os, sets, strformat, strutils],
  guildy,
  jsony,
  ./[agent_runner, architect_agent, chat_common, config, git_ops, intent_classifier,
     lock_management, notifications, prompt_builders, shared_state]

const
  DiscordMessageLimit = 2000
  SpecUpdatedNote = "\n[spec.md updated]"
  DiscordChatTicketId = "discord-chat"
  InteractionResponseMessage = 4
  MaxProcessedMessageIds = 500

var
  processedMessageIds {.global.}: HashSet[string]
  processedMessageIdQueue {.global.}: seq[string]
  processedMessageLock {.global.}: Lock

type
  ChatThreadArgs = tuple[repoPath: string, token: string, channelId: string, messageText: string, mode: ChatMode, explicit: bool, username: string, chatHistoryCount: int, messageId: string]
  NotificationPollerArgs = tuple[repoPath: string, token: string, channelId: string]

proc truncateMessage(msg: string): string =
  ## Truncate a message to fit within the Discord message character limit.
  result = chat_common.truncateMessage(msg, DiscordMessageLimit)

proc registerSlashCommands(c: GuildyClient, serverId: string) =
  ## Register slash commands with Discord after gateway READY.
  ## When serverId is set, registers as guild commands (instant). Otherwise global (slow propagation).
  let commands = @[
    SlashCommand(name: "status", description: "Show orchestrator status and ticket counts", `type`: 1),
    SlashCommand(name: "queue", description: "Show merge queue and ticket lists", `type`: 1),
    SlashCommand(name: "pause", description: "Pause the orchestrator", `type`: 1),
    SlashCommand(name: "resume", description: "Resume the orchestrator", `type`: 1),
    SlashCommand(name: "help", description: "Show available commands", `type`: 1),
    SlashCommand(name: "restart", description: "Restart the bot process", `type`: 1),
  ]
  discard c.registerCommands(toJson(commands), serverId)
  echo "scriptorium: registered slash commands"

proc fetchDiscordHistory(client: GuildyClient, channelId: string, count: int, currentMessageId: string): seq[PlanTurn] =
  ## Fetch recent channel messages and convert to PlanTurn history.
  ## Excludes the current message by ID and filters to default message type only.
  if count <= 0:
    return @[]
  # Fetch extra to account for filtering.
  let messages = client.getChannelMessages(channelId, count + 1)
  # Messages are newest-first from Discord API.
  var turns: seq[PlanTurn] = @[]
  for msg in messages:
    if msg.id == currentMessageId:
      continue
    if msg.`type` != 0:
      continue
    let role = if msg.author.bot: "architect" else: msg.author.username
    let text = msg.content.strip()
    if text.len > 0 and turns.len < count:
      turns.add(PlanTurn(role: role, text: text))
  # Reverse to chronological order (oldest first).
  turns.reverse()
  result = turns

proc handleChatMessage(repoPath: string, client: GuildyClient, channelId: string, messageText: string, username: string, history: seq[PlanTurn]) =
  ## Invoke the architect with a chat message and post the response to the channel.
  let cfg = loadConfig(repoPath)
  var specChanged = false
  var response = ""
  try:
    response = withLockedPlanWorktree(repoPath, proc(planPath: string): string =
      let existingSpec = loadSpecFromPlanPath(planPath)
      let prompt = buildInteractivePlanPrompt(repoPath, planPath, existingSpec, history, messageText, username)
      let agentResult = runPlanArchitectRequest(
        runAgent,
        repoPath,
        planPath,
        cfg.agents.architect,
        prompt,
        DiscordChatTicketId,
      )
      if cfg.devops.enabled:
        enforceWritePrefixAllowlist(planPath, [PlanSpecPath, PlanTicketsOpenDir, "services"], PlanWriteScopeName)
      else:
        enforceWritePrefixAllowlist(planPath, [PlanSpecPath, PlanTicketsOpenDir], PlanWriteScopeName)

      # Commit any new tickets created by the architect.
      gitRun(planPath, "add", PlanTicketsOpenDir)
      if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
        gitRun(planPath, "commit", "-m", "scriptorium: architect created tickets")

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

proc handleAskMessage(repoPath: string, client: GuildyClient, channelId: string, messageText: string, username: string, history: seq[PlanTurn]) =
  ## Invoke the architect in read-only mode and post the response to the channel.
  let cfg = loadConfig(repoPath)
  var response = ""
  try:
    response = withLockedPlanWorktree(repoPath, proc(planPath: string): string =
      let spec = loadSpecFromPlanPath(planPath)
      let prompt = buildInteractiveAskPrompt(repoPath, planPath, spec, history, messageText, username)
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

proc handleDoMessage(repoPath: string, client: GuildyClient, channelId: string, messageText: string, username: string, history: seq[PlanTurn]) =
  ## Invoke the architect with full repo access and post the response to the channel.
  {.cast(gcsafe).}:
    let cfg = loadConfig(repoPath)
    var response = ""
    try:
      let prompt = buildInteractiveDoPrompt(repoPath, history, messageText, username, cfg.devops.enabled)
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

proc handleChatResponse(repoPath: string, client: GuildyClient, channelId: string, messageText: string, username: string, history: seq[PlanTurn]) =
  ## Handle casual chat messages using the architect in read-only ask mode.
  ## No worktree locking, no plan branch writes — lightweight conversational response.
  {.cast(gcsafe).}:
    let cfg = loadConfig(repoPath)
    var response = ""
    try:
      response = withLockedPlanWorktree(repoPath, proc(planPath: string): string =
        let spec = loadSpecFromPlanPath(planPath)
        let prompt = buildInteractiveAskPrompt(repoPath, planPath, spec, history, messageText, username)
        let agentResult = runPlanArchitectRequest(
          runAgent,
          repoPath,
          planPath,
          cfg.agents.architect,
          prompt,
          DiscordChatTicketId,
        )
        enforceNoWrites(planPath, "scriptorium discord chat")

        var reply = agentResult.lastMessage.strip()
        if reply.len == 0:
          reply = agentResult.stdout.strip()
        if reply.len == 0:
          reply = "(no response)"
        reply
      )
    except CatchableError as e:
      let errMsg = e.msg
      echo &"scriptorium: discord chat error: {errMsg}"
      response = &"Error: {errMsg}"

    discard client.postChannelMessage(channelId, response)

proc notificationPollerThread(args: NotificationPollerArgs) {.thread.} =
  ## Poll for notification files and post them to the channel.
  let client = newGuildyClient(args.token)
  while true:
    sleep(5000)
    try:
      let messages = consumeNotifications(args.repoPath)
      for msg in messages:
        discard client.postChannelMessage(args.channelId, msg)
    except CatchableError as e:
      echo &"scriptorium: notification poller error: {e.msg}"

proc chatWorkerThread(args: ChatThreadArgs) {.thread.} =
  ## Run architect chat in a background thread, routed by mode.
  ## When the mode prefix was not explicit, runs intent classification first.
  let restClient = newGuildyClient(args.token)
  let history = fetchDiscordHistory(restClient, args.channelId, args.chatHistoryCount, args.messageId)

  var mode = args.mode
  if not args.explicit:
    let cfg = loadConfig(args.repoPath)
    let intent = classifyIntent(runAgent, args.repoPath, args.messageText, history, args.username, cfg.devops.enabled)
    echo &"scriptorium: classified intent for {args.username}: {intent}"
    case intent
    of intentIgnore: mode = chatModeIgnore
    of intentChat: mode = chatModeChat
    of intentAsk: mode = chatModeAsk
    of intentPlan: mode = chatModePlan
    of intentDo: mode = chatModeDo

  case mode
  of chatModePlan:
    handleChatMessage(args.repoPath, restClient, args.channelId, args.messageText, args.username, history)
  of chatModeAsk:
    handleAskMessage(args.repoPath, restClient, args.channelId, args.messageText, args.username, history)
  of chatModeDo:
    handleDoMessage(args.repoPath, restClient, args.channelId, args.messageText, args.username, history)
  of chatModeChat:
    handleChatResponse(args.repoPath, restClient, args.channelId, args.messageText, args.username, history)
  of chatModeIgnore:
    echo &"scriptorium: ignoring message from {args.username} (classified as human-to-human)"

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

  initLock(processedMessageLock)

  clearNotifications(repoPath)
  let pollerPtr = create(Thread[NotificationPollerArgs])
  createThread(pollerPtr[], notificationPollerThread, (repoPath, token, channelId))

  let onMessage = proc(c: GuildyClient, msg: DiscordMessage) {.gcsafe.} =
    if msg.channel_id != channelId:
      return
    if msg.author.bot:
      return
    # Dedup: guildy fires onMessage for both MESSAGE_CREATE and MESSAGE_UPDATE.
    # Discord link preview embeds trigger MESSAGE_UPDATE, causing duplicate processing.
    {.cast(gcsafe).}:
      withLock processedMessageLock:
        if msg.id in processedMessageIds:
          return
        processedMessageIds.incl(msg.id)
        processedMessageIdQueue.add(msg.id)
        if processedMessageIdQueue.len > MaxProcessedMessageIds:
          let oldest = processedMessageIdQueue[0]
          processedMessageIdQueue.delete(0)
          processedMessageIds.excl(oldest)
    if allowedUserIds.len > 0 and msg.author.id notin allowedUserIds:
      let ignoredUser = msg.author.username
      let ignoredId = msg.author.id
      echo &"scriptorium: discord message ignored from non-allowlisted user {ignoredUser} ({ignoredId})"
      return
    let user = msg.author.username
    let content = msg.content
    let (mode, text, explicit) = parseChatMode(content)
    echo &"scriptorium: discord message from {user} (mode={mode}): {text}"
    # Spawn background thread to avoid blocking the gateway event loop.
    let threadPtr = create(Thread[ChatThreadArgs])
    let historyCount = cfg.discord.chatHistoryCount
    let msgId = msg.id
    createThread(threadPtr[], chatWorkerThread, (repoPath, token, channelId, text, mode, explicit, user, historyCount, msgId))

  let onInteraction = proc(c: GuildyClient, interaction: DiscordInteraction) {.gcsafe.} =
    if interaction.channel_id != channelId:
      return
    if allowedUserIds.len > 0 and interaction.user_id notin allowedUserIds:
      echo &"scriptorium: discord interaction ignored from non-allowlisted user ({interaction.user_id})"
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
    of "help":
      response = handleHelp()
    of "restart":
      c.respondToInteraction(interaction.id, interaction.token, InteractionResponseMessage, "Restarting...")
      handleRestart()
      return
    else:
      response = "Unknown command."
    let truncated = truncateMessage(response)
    c.respondToInteraction(interaction.id, interaction.token, InteractionResponseMessage, truncated)

  echo "scriptorium: starting Discord bot"
  client.startGateway(onRaw = onRaw, onMessage = onMessage, onInteraction = onInteraction)
