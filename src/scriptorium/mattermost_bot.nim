import
  std/[algorithm, json, os, strformat, strutils, tables],
  mosty,
  ./[agent_runner, architect_agent, chat_common, config, git_ops, intent_classifier,
     lock_management, prompt_builders, shared_state]

const
  MattermostMessageLimit = 16383
  SpecUpdatedNote = "\n[spec.md updated]"
  MattermostChatTicketId = "mattermost-chat"

type
  ChatThreadArgs = tuple[repoPath: string, url: string, token: string, channelId: string, messageText: string, mode: ChatMode, explicit: bool, userId: string, botUserId: string, chatHistoryCount: int, postId: string]

proc truncateMessage(msg: string): string =
  ## Truncate a message to fit within the Mattermost message character limit.
  result = chat_common.truncateMessage(msg, MattermostMessageLimit)

proc fetchMattermostHistory(client: MostyClient, channelId: string, count: int, botUserId: string, currentPostId: string): seq[PlanTurn] =
  ## Fetch recent channel posts and convert to PlanTurn history.
  ## Excludes the current post by ID and filters to normal posts only.
  if count <= 0:
    return @[]
  # Fetch extra to account for filtering.
  let postList = client.getChannelPosts(channelId, 0, count + 1)
  # Order is newest-first.
  var turns: seq[PlanTurn] = @[]
  for id in postList.order:
    if id == currentPostId:
      continue
    if not postList.posts.hasKey(id):
      continue
    let post = postList.posts[id]
    if post.post_type.len > 0:
      continue
    let text = post.message.strip()
    if text.len == 0:
      continue
    if turns.len >= count:
      break
    let role =
      if post.user_id == botUserId: "architect"
      else:
        let user = client.getUser(post.user_id)
        user.username
    turns.add(PlanTurn(role: role, text: text))
  # Reverse to chronological order (oldest first).
  turns.reverse()
  result = turns

proc handleChatMessage(repoPath: string, client: MostyClient, channelId: string, messageText: string, username: string, history: seq[PlanTurn]) =
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
        MattermostChatTicketId,
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
    echo &"scriptorium: mattermost architect error: {errMsg}"
    response = &"Error: {errMsg}"

  if specChanged:
    response = response & SpecUpdatedNote
  let truncated = truncateMessage(response)
  discard client.createPost(channelId, truncated)

proc handleAskMessage(repoPath: string, client: MostyClient, channelId: string, messageText: string, username: string, history: seq[PlanTurn]) =
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
        MattermostChatTicketId,
      )
      enforceNoWrites(planPath, "scriptorium mattermost ask")

      var reply = agentResult.lastMessage.strip()
      if reply.len == 0:
        reply = agentResult.stdout.strip()
      if reply.len == 0:
        reply = "(no response from architect)"
      reply
    )
  except CatchableError as e:
    let errMsg = e.msg
    echo &"scriptorium: mattermost ask error: {errMsg}"
    response = &"Error: {errMsg}"

  let truncated = truncateMessage(response)
  discard client.createPost(channelId, truncated)

proc handleDoMessage(repoPath: string, client: MostyClient, channelId: string, messageText: string, username: string, history: seq[PlanTurn]) =
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
        MattermostChatTicketId,
      )
      response = agentResult.lastMessage.strip()
      if response.len == 0:
        response = agentResult.stdout.strip()
      if response.len == 0:
        response = "(no response from architect)"
    except CatchableError as e:
      let errMsg = e.msg
      echo &"scriptorium: mattermost do error: {errMsg}"
      response = &"Error: {errMsg}"

    let truncated = truncateMessage(response)
    discard client.createPost(channelId, truncated)

proc handleChatResponse(repoPath: string, client: MostyClient, channelId: string, messageText: string, username: string, history: seq[PlanTurn]) =
  ## Handle casual chat messages using the architect in read-only ask mode.
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
          MattermostChatTicketId,
        )
        enforceNoWrites(planPath, "scriptorium mattermost chat")

        var reply = agentResult.lastMessage.strip()
        if reply.len == 0:
          reply = agentResult.stdout.strip()
        if reply.len == 0:
          reply = "(no response)"
        reply
      )
    except CatchableError as e:
      let errMsg = e.msg
      echo &"scriptorium: mattermost chat error: {errMsg}"
      response = &"Error: {errMsg}"

    let truncated = truncateMessage(response)
    discard client.createPost(channelId, truncated)

proc chatWorkerThread(args: ChatThreadArgs) {.thread.} =
  ## Run architect chat in a background thread, routed by mode.
  ## When the mode prefix was not explicit, runs intent classification first.
  let restClient = newMostyClient(args.url, args.token)
  let user = restClient.getUser(args.userId)
  let username = user.username
  let history = fetchMattermostHistory(restClient, args.channelId, args.chatHistoryCount, args.botUserId, args.postId)

  var mode = args.mode
  if not args.explicit:
    let cfg = loadConfig(args.repoPath)
    let intent = classifyIntent(runAgent, args.repoPath, args.messageText, history, username, cfg.devops.enabled)
    echo &"scriptorium: classified intent for {username}: {intent}"
    case intent
    of intentIgnore: mode = chatModeIgnore
    of intentChat: mode = chatModeChat
    of intentAsk: mode = chatModeAsk
    of intentPlan: mode = chatModePlan
    of intentDo: mode = chatModeDo

  case mode
  of chatModePlan:
    handleChatMessage(args.repoPath, restClient, args.channelId, args.messageText, username, history)
  of chatModeAsk:
    handleAskMessage(args.repoPath, restClient, args.channelId, args.messageText, username, history)
  of chatModeDo:
    handleDoMessage(args.repoPath, restClient, args.channelId, args.messageText, username, history)
  of chatModeChat:
    handleChatResponse(args.repoPath, restClient, args.channelId, args.messageText, username, history)
  of chatModeIgnore:
    echo &"scriptorium: ignoring message from {username} (classified as human-to-human)"

proc handleCommand(client: MostyClient, repoPath: string, channelId: string, cmd: string) =
  ## Handle a !command prefix message and post the response.
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
    discard client.createPost(channelId, "Restarting...")
    handleRestart()
    return
  else:
    response = &"Unknown command: !{cmd}"
  let truncated = truncateMessage(response)
  discard client.createPost(channelId, truncated)

proc runMattermostBot*(repoPath: string) =
  ## Start the Mattermost bot gateway connection.
  let token = getEnv("MATTERMOST_TOKEN")
  if token.len == 0:
    echo "scriptorium: MATTERMOST_TOKEN environment variable is required"
    quit(1)

  let cfg = loadConfig(repoPath)
  let url = cfg.mattermost.url
  if url.len == 0:
    echo "scriptorium: mattermost.url is required in scriptorium.json"
    quit(1)

  let channelId = cfg.mattermost.channelId
  if channelId.len == 0:
    echo "scriptorium: mattermost.channelId is required in scriptorium.json"
    quit(1)

  let allowedUserIds = cfg.mattermost.allowedUserIds
  enablePartialChainVerification()
  let client = newMostyClient(url, token)

  # Get the bot's own user ID so we can ignore our own messages.
  let me = client.getMe()
  let botUserId = me.id
  echo &"scriptorium: mattermost bot user: {me.username} ({botUserId})"

  let onPost = proc(c: MostyClient, post: MattermostPost) {.gcsafe.} =
    if post.channel_id != channelId:
      return
    if post.user_id == botUserId:
      return
    if allowedUserIds.len > 0 and post.user_id notin allowedUserIds:
      echo &"scriptorium: mattermost message ignored from non-allowlisted user ({post.user_id})"
      return

    let content = post.message.strip()
    if content.len == 0:
      return

    # Handle !command prefixes.
    if content.startsWith("!"):
      let cmd = content[1..^1].strip().toLowerAscii().split(" ")[0]
      echo &"scriptorium: mattermost command !{cmd}"
      handleCommand(c, repoPath, channelId, cmd)
      return

    # Parse chat mode and spawn background thread.
    let (mode, text, explicit) = parseChatMode(content)
    echo &"scriptorium: mattermost message from {post.user_id} (mode={mode}): {text}"
    let threadPtr = create(Thread[ChatThreadArgs])
    let historyCount = cfg.mattermost.chatHistoryCount
    let currentPostId = post.id
    createThread(threadPtr[], chatWorkerThread, (repoPath, url, token, channelId, text, mode, explicit, post.user_id, botUserId, historyCount, currentPostId))

  echo "scriptorium: starting Mattermost bot"
  client.startGateway(onPost = onPost)
