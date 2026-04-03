import
  std/[json, os, strformat, strutils],
  mosty,
  ./[agent_runner, architect_agent, chat_common, config, git_ops, lock_management,
     prompt_builders, shared_state]

const
  MattermostMessageLimit = 16383
  SpecUpdatedNote = "\n[spec.md updated]"
  MattermostChatTicketId = "mattermost-chat"

type
  ChatThreadArgs = tuple[repoPath: string, url: string, token: string, channelId: string, messageText: string, mode: ChatMode, userId: string]

proc truncateMessage(msg: string): string =
  ## Truncate a message to fit within the Mattermost message character limit.
  result = chat_common.truncateMessage(msg, MattermostMessageLimit)

proc handleChatMessage(repoPath: string, client: MostyClient, channelId: string, messageText: string, username: string) =
  ## Invoke the architect with a chat message and post the response to the channel.
  let cfg = loadConfig(repoPath)
  var specChanged = false
  var response = ""
  try:
    response = withLockedPlanWorktree(repoPath, proc(planPath: string): string =
      let existingSpec = loadSpecFromPlanPath(planPath)
      let prompt = buildArchitectPlanPrompt(repoPath, planPath, messageText, existingSpec, username)
      let agentResult = runPlanArchitectRequest(
        runAgent,
        repoPath,
        planPath,
        cfg.agents.architect,
        prompt,
        MattermostChatTicketId,
      )
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

proc handleAskMessage(repoPath: string, client: MostyClient, channelId: string, messageText: string, username: string) =
  ## Invoke the architect in read-only mode and post the response to the channel.
  let cfg = loadConfig(repoPath)
  var response = ""
  try:
    response = withLockedPlanWorktree(repoPath, proc(planPath: string): string =
      let spec = loadSpecFromPlanPath(planPath)
      let prompt = buildInteractiveAskPrompt(repoPath, planPath, spec, @[], messageText, username)
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

proc handleDoMessage(repoPath: string, client: MostyClient, channelId: string, messageText: string, username: string) =
  ## Invoke the architect with full repo access and post the response to the channel.
  {.cast(gcsafe).}:
    let cfg = loadConfig(repoPath)
    var response = ""
    try:
      let prompt = buildDoOneShotPrompt(repoPath, messageText, username)
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

proc chatWorkerThread(args: ChatThreadArgs) {.thread.} =
  ## Run architect chat in a background thread, routed by mode.
  let restClient = newMostyClient(args.url, args.token)
  let user = restClient.getUser(args.userId)
  let username = user.username
  case args.mode
  of chatModePlan:
    handleChatMessage(args.repoPath, restClient, args.channelId, args.messageText, username)
  of chatModeAsk:
    handleAskMessage(args.repoPath, restClient, args.channelId, args.messageText, username)
  of chatModeDo:
    handleDoMessage(args.repoPath, restClient, args.channelId, args.messageText, username)

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
    let (mode, text) = parseChatMode(content)
    echo &"scriptorium: mattermost message from {post.user_id} (mode={mode}): {text}"
    let threadPtr = create(Thread[ChatThreadArgs])
    createThread(threadPtr[], chatWorkerThread, (repoPath, url, token, channelId, text, mode, post.user_id))

  echo "scriptorium: starting Mattermost bot"
  client.startGateway(onPost = onPost)
