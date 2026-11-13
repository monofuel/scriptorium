import
  std/[json, monotimes, options, os, sha1, strtabs, strutils, tables, times],
  acport,
  ./[acp_permissions, agent_runner_types, agent_sessions, agent_usage, config]

const
  SetupTimeoutMs = 60_000
  CancelGraceMs = 5000
  PollIntervalMs = 25
  ClientVersion = "20.0.0-dev"

type
  PacketKind = enum
    updatePacket, diagnosticPacket, permissionPacket
  CallbackPacket = object
    kind: PacketKind
    text: string
  CallbackBridge = object
    packets: Channel[CallbackPacket]
    policy: AgentAccessPolicy
    scope: cstring
  AgentConversation* = ref object
    client: AcpClient
    session: AcpSession
    bridge: ptr CallbackBridge
    identity: string
    closed: bool
    logDirectory: string
    toolTitles: Table[string, string]

proc saveSetupPackets(conversation: AgentConversation, phase: string) =
  ## Retain replay and setup diagnostics without printing child stderr.
  if conversation.bridge == nil: return
  createDir(conversation.logDirectory)
  let
    transcript = open(conversation.logDirectory / (phase & ".jsonl"), fmAppend)
    diagnostics = open(conversation.logDirectory / (phase & ".stderr.log"), fmAppend)
  defer:
    transcript.close()
    diagnostics.close()
  while true:
    let (received, packet) = conversation.bridge.packets.tryRecv()
    if not received: break
    if packet.kind == diagnosticPacket: diagnostics.write(packet.text)
    else: transcript.writeLine(packet.text)

proc sharedScope(request: AgentRunRequest): cstring =
  ## Copy immutable permission context into explicitly owned shared storage.
  let text = $(%*{"cwd": absolutePath(request.workingDir), "paths": request.allowedWritePaths})
  result = cast[cstring](allocShared0(text.len + 1))
  if text.len > 0: copyMem(result, unsafeAddr text[0], text.len)

proc captureUpdate(update: SessionUpdate, userData: pointer) {.gcsafe.} =
  ## Transfer callback payloads through a channel to the owning runner thread.
  let bridge = cast[ptr CallbackBridge](userData)
  bridge.packets.send(CallbackPacket(kind: updatePacket, text: $update.toJsonNode()))

proc captureDiagnostic(userData: pointer, message: string) {.gcsafe.} =
  ## Transfer stderr separately from protocol activity.
  let bridge = cast[ptr CallbackBridge](userData)
  bridge.packets.send(CallbackPacket(kind: diagnosticPacket, text: message))

proc decidePermission(context: RequestContext, request: PermissionRequest,
    userData: pointer): PermissionOutcome {.gcsafe.} =
  ## Apply immutable operation policy on the permission request worker.
  if context.isCancelled(): return PermissionOutcome(outcome: "cancelled")
  let
    bridge = cast[ptr CallbackBridge](userData)
    scope = parseJson($bridge.scope)
  var paths: seq[string]
  for path in scope["paths"]: paths.add(path.getStr())
  result = permissionOutcome(request, bridge.policy, scope["cwd"].getStr(), paths)
  bridge.packets.send(CallbackPacket(kind: permissionPacket,
    text: $(%*{"permission": request.toJsonNode(), "decision": result.toJsonNode()})))

proc close*(conversation: AgentConversation) =
  ## Join callbacks before destroying the application-owned shared bridge.
  if conversation.isNil or conversation.closed: return
  conversation.closed = true
  if conversation.client != nil:
    conversation.client.close()
    conversation.client = nil
  conversation.saveSetupPackets("shutdown")
  if conversation.bridge != nil:
    conversation.bridge.packets.close()
    deallocShared(conversation.bridge.scope)
    deallocShared(conversation.bridge)
    conversation.bridge = nil

proc mcpServers*(endpoint: string): seq[JsonNode] =
  ## Carry a scoped HTTP MCP connection through standard ACP session requests.
  let base = endpoint.strip().strip(leading = false, trailing = true, chars = {'/'})
  if base.len > 0:
    result.add(%*{"type": "http", "name": "scriptorium",
      "url": base & "/mcp", "headers": []})

proc normalizeRequest*(request: AgentRunRequest): AgentRunRequest =
  ## Resolve direct API requests using the same profiles as configured roles.
  result = request
  if result.workingDir.len == 0:
    raise newException(ValueError, "workingDir is required")
  result.workingDir = absolutePath(result.workingDir)
  if result.acpAgent.len == 0: result.acpAgent = profileName(result.harness)
  if result.profile.command.len == 0:
    let profiles = defaultAcpAgents()
    if not profiles.hasKey(result.acpAgent):
      raise newException(ValueError, "Missing ACP profile: " & result.acpAgent)
    result.profile = profiles[result.acpAgent]
  if result.binary.len > 0: result.profile.command = result.binary
  if result.allowedTools.len > 0: result.accessPolicy = accessReadOnly
  if result.accessPolicy == accessReadOnly:
    result.profile.args = result.profile.readOnlyArgs & result.profile.args
  if result.attempt <= 0: result.attempt = 1
  if result.logRoot.len == 0:
    result.logRoot = runtimeStateDirectory(result.workingDir) / "logs" / "agents"

proc configOptionId(session: AcpSession, category, explicitId: string): string =
  ## Discover options by category or explicitly configured identifiers.
  for option in session.getConfigOptions():
    if (explicitId.len > 0 and option.id == explicitId) or
        (explicitId.len == 0 and option.category.get("") == category):
      return option.id
  if explicitId.len > 0:
    raise newException(ValueError, "ACP agent did not advertise config option: " & explicitId)

proc setupTimeout(started: MonoTime): int =
  ## Give the whole handshake one deadline instead of one per RPC.
  result = SetupTimeoutMs - int((getMonoTime() - started).inMilliseconds)
  if result <= 0: raise newException(AcpTimeoutError, "ACP setup deadline exceeded")

proc setSelection(session: AcpSession, category, id, value: string, started: MonoTime) =
  ## Apply explicit values without silently changing the selected model.
  if value.len == 0: return
  let optionId = configOptionId(session, category, id)
  if optionId.len == 0:
    raise newException(ValueError, "ACP agent does not expose requested " & category & " configuration")
  discard session.setConfigOption(optionId, value, setupTimeout(started))

proc configureSession(conversation: AgentConversation, request: AgentRunRequest, started: MonoTime) =
  ## Set model before dependent effort choices and establish operation access.
  let session = conversation.session
  session.setSelection("model", request.profile.modelOption, request.model, started)
  session.setSelection("thought_level", request.profile.effortOption, request.reasoningEffort, started)
  for id, value in request.configOptions:
    if id == "mode":
      raise newException(ValueError, "Configure access through the ACP profile, not a mode override")
    case value.kind
    of JString: discard session.setConfigOption(id, value.getStr(), setupTimeout(started))
    of JBool: discard session.setConfigOption(id, value.getBool(), setupTimeout(started))
    else: raise newException(ValueError, "ACP config values must be strings or booleans: " & id)
  let
    restricted = request.accessPolicy == accessReadOnly
    mode = if restricted: request.profile.readOnlyMode else: request.profile.writeMode
    optionId = configOptionId(session, "mode", "")
  if mode.len == 0:
    if restricted:
      raise newException(ValueError, "Restricted ACP operations require readOnlyMode")
  elif optionId.len > 0:
    discard session.setConfigOption(optionId, mode, setupTimeout(started))
  elif session.getModes().isSome():
    session.setMode(mode, setupTimeout(started))
  elif restricted and request.profile.readOnlyArgs.len == 0:
    raise newException(ValueError, "ACP agent has no enforceable restricted mode")

proc executablePath*(command: string): string =
  ## Prefer pinned local tools while allowing explicit executable paths.
  if command.isAbsolute() or DirSep in command: return absolutePath(command)
  let local = getCurrentDir() / ".build" / "agent-tools" / "node_modules" / ".bin" / command
  if fileExists(local): return local
  result = findExe(command)
  if result.len == 0:
    raise newException(ValueError, "ACP executable not found: " & command & "; run make agent-setup")

proc openConversation*(rawRequest: AgentRunRequest): AgentConversation =
  ## Open a conversation with fresh scoped MCP configuration and matching identity.
  let request = normalizeRequest(rawRequest)
  new(result)
  result.identity = sessionIdentity(request)
  result.logDirectory = request.logRoot / $secureHash(request.ticketId)
  result.bridge = cast[ptr CallbackBridge](allocShared0(sizeof(CallbackBridge)))
  result.bridge.policy = request.accessPolicy
  result.bridge.scope = sharedScope(request)
  result.bridge.packets.open()
  result.client = newAcpClient("scriptorium", ClientVersion,
    ClientHandlers(onUpdate: captureUpdate, onPermission: decidePermission,
      onLog: captureDiagnostic, userData: result.bridge))
  try:
    let environment = newStringTable(modeCaseSensitive)
    for key, value in request.profile.env: environment[key] = value
    if request.homeDirectory.len > 0: environment["HOME"] = request.homeDirectory
    if request.acpAgent == "claude": environment["CLAUDECODE"] = ""
    if request.profile.command == "codex-acp" and getEnv("CODEX_PATH").len == 0 and
        not environment.hasKey("CODEX_PATH"):
      environment["CODEX_PATH"] = executablePath("codex")
    if request.profile.command == "claude-agent-acp" and
        getEnv("CLAUDE_CODE_EXECUTABLE").len == 0 and
        not environment.hasKey("CLAUDE_CODE_EXECUTABLE"):
      environment["CLAUDE_CODE_EXECUTABLE"] = executablePath("claude")
    result.client.connect(executablePath(request.profile.command), request.profile.args,
      workingDir = request.workingDir, environment = environment, workerThreads = 2)
    let started = getMonoTime()
    let initialized = result.client.initialize(setupTimeout(started))
    var authMethod = request.profile.authMethod
    if authMethod.len == 0 and request.acpAgent == "grok" and request.profile.command == "grok":
      authMethod = if getEnv("XAI_API_KEY").len > 0 or
        request.profile.env.getOrDefault("XAI_API_KEY").len > 0: "xai.api_key" else: "cached_token"
    if authMethod.len > 0:
      result.client.authenticate(authMethod, setupTimeout(started), meta = %*{"headless": true})
    let record = if request.restoreSession or request.resumeSessionId.len > 0:
      readSessionRecord(request) else: AgentSessionRecord()
    if record.sessionId.len > 0 and not record.completed and
        initialized.agentCapabilities.getOrDefault("loadSession").getBool():
      result.session = result.client.loadSession(record.sessionId, request.workingDir,
        mcpServers(request.mcpEndpoint), setupTimeout(started))
    else:
      if record.sessionId.len > 0:
        stderr.writeLine("scriptorium: starting a fresh ACP recovery conversation; session loading unavailable")
      result.session = result.client.newSession(request.workingDir,
        mcpServers(request.mcpEndpoint), setupTimeout(started))
    result.configureSession(request, started)
    result.saveSetupPackets("setup")
    saveSessionRecord(request, result.session.id)
  except CatchableError:
    result.saveSetupPackets("setup")
    result.close()
    raise

proc streamEvent*(update: SessionUpdate): AgentStreamEvent =
  ## Preserve structured updates while presenting concise display text.
  result.update = update
  result.rawLine = $update.toJsonNode()
  case update.kind
  of agentMessageChunk:
    result.kind = agentEventMessage
    if update.content.kind == textContent: result.text = update.content.text
  of agentThoughtChunk:
    result.kind = agentEventReasoning
    if update.content.kind == textContent: result.text = update.content.text
  of toolCall, toolCallUpdate:
    result.kind = agentEventTool
    result.text = update.tool.title
    if update.tool.status.len > 0: result.text.add(" " & update.tool.status)
  of planUpdate:
    result.kind = agentEventPlan
    for entry in update.entries:
      result.text.add(entry.status & ": " & entry.content & "\n")
  of userMessageChunk: result.kind = agentEventStatus
  of unknownUpdate: result.kind = agentEventUnknown

proc configurationOptions*(conversation: AgentConversation): seq[SessionConfigOption] =
  ## Return an owned catalog for model selectors and integration diagnostics.
  conversation.session.getConfigOptions()

proc elapsedMs(start: MonoTime): int64 =
  ## Measure watchdog intervals using a monotonic clock.
  (getMonoTime() - start).inMilliseconds

proc drainPackets(conversation: AgentConversation, request: AgentRunRequest,
    runResult: var AgentRunResult, transcript, diagnostics: File,
    lastOutput, lastTool: var MonoTime) =
  ## Drain ordered callbacks, including updates immediately preceding completion.
  while true:
    let (received, packet) = conversation.bridge.packets.tryRecv()
    if not received: break
    if packet.kind == diagnosticPacket:
      diagnostics.write(packet.text)
    else:
      transcript.writeLine(packet.text)
      runResult.outputBytes += packet.text.len + 1
      recordOutputBytes(packet.text.len + 1)
      lastOutput = getMonoTime()
      if packet.kind == updatePacket:
        var event = streamEvent(parseUpdate(parseJson(packet.text)))
        if event.kind == agentEventTool:
          let tool = event.update.tool
          if tool.title.len > 0:
            conversation.toolTitles[tool.toolCallId] = tool.title
          event.text = conversation.toolTitles.getOrDefault(tool.toolCallId, "tool")
          if tool.status.len > 0: event.text.add(" " & tool.status)
          lastTool = lastOutput
        if event.kind == agentEventMessage: runResult.lastMessage.add(event.text)
        if not request.onEvent.isNil: request.onEvent(event)
  transcript.flushFile()

proc runTurn*(conversation: AgentConversation, rawRequest: AgentRunRequest): AgentRunResult =
  ## Run one native turn while draining events and enforcing watchdogs.
  let request = normalizeRequest(rawRequest)
  if conversation.isNil or conversation.closed:
    raise newException(ValueError, "ACP conversation is closed")
  if conversation.identity != sessionIdentity(request):
    raise newException(ValueError, "Cannot reuse an ACP conversation across operation boundaries")
  let
    logDirectory = request.logRoot / $secureHash(request.ticketId)
    prefix = "attempt-" & $request.attempt
  createDir(logDirectory)
  result = AgentRunResult(backend: request.harness, acpAgent: request.acpAgent,
    sessionId: conversation.session.id, attempt: request.attempt, attemptCount: 1,
    command: @[request.profile.command] & request.profile.args, timeoutKind: "none",
    logFile: logDirectory / (prefix & ".jsonl"),
    lastMessageFile: logDirectory / (prefix & ".last_message.txt"))
  for option in conversation.configurationOptions():
    if option.category.get("") == "model" and option.currentValue.kind == stringConfigValue:
      result.model = option.currentValue.stringValue
  let
    transcript = open(result.logFile, fmAppend)
    diagnostics = open(logDirectory / (prefix & ".stderr.log"), fmAppend)
  defer:
    transcript.close()
    diagnostics.close()
  var
    started = getMonoTime()
    lastOutput = started
    lastTool = started
    lastHeartbeat = started
    cancelStarted = started
    cancelling = false
    handle = conversation.session.startPrompt(@[textBlock(request.prompt)])
    consumed = false
  try:
    while true:
      conversation.drainPackets(request, result, transcript, diagnostics, lastOutput, lastTool)
      if handle.isReady(): break
      if not cancelling:
        if not request.cancellationRequested.isNil and request.cancellationRequested():
          result.cancelled = true
          result.failureKind = failureCancelled
          cancelling = true
        elif request.hardTimeoutMs > 0 and elapsedMs(started) >= request.hardTimeoutMs:
          result.timeoutKind = "hard"
          cancelling = true
        elif request.noOutputTimeoutMs > 0 and elapsedMs(lastOutput) >= request.noOutputTimeoutMs:
          result.timeoutKind = "no-output"
          cancelling = true
        elif request.progressTimeoutMs > 0 and elapsedMs(lastTool) >= request.progressTimeoutMs:
          result.timeoutKind = "progress"
          cancelling = true
        if cancelling:
          if not result.cancelled: result.failureKind = failureTimeout
          cancelStarted = getMonoTime()
          conversation.session.cancel()
      elif elapsedMs(cancelStarted) >= CancelGraceMs:
        conversation.close()
        break
      if request.heartbeatIntervalMs > 0 and elapsedMs(lastHeartbeat) >= request.heartbeatIntervalMs:
        if not request.onEvent.isNil:
          request.onEvent(AgentStreamEvent(kind: agentEventHeartbeat, text: "still working"))
        lastHeartbeat = getMonoTime()
      sleep(PollIntervalMs)
    consumed = true
    let completion = handle.waitForPrompt()
    if not conversation.closed:
      conversation.drainPackets(request, result, transcript, diagnostics, lastOutput, lastTool)
    result.stopReason = completion.stopReason
    if result.failureKind == failureNone:
      case result.stopReason
      of endTurn: discard
      of cancelled:
        result.cancelled = true
        result.failureKind = failureCancelled
      of refused: result.failureKind = failureRefused
      of maxTokens, maxTurnRequests: result.failureKind = failureLimit
  except AcpRpcError as error:
    result.failureKind = failureRpc
    result.errorCode = error.code
    result.errorData = error.data
    result.errorMessage = error.msg
  except AcpProtocolError as error:
    result.failureKind = failureProtocol
    result.errorMessage = error.msg
  except AcpTransportError as error:
    if result.failureKind == failureNone: result.failureKind = failureTransport
    result.errorMessage = error.msg
  finally:
    if not consumed:
      conversation.close()
      try:
        discard handle.waitForPrompt()
      except AcpError as error:
        diagnostics.writeLine("ACP cleanup settled the pending turn: " & error.msg)
  result.exitCode = if result.failureKind == failureNone: 0 else: 1
  transcript.writeLine($(%*{"event": "completion", "sessionId": result.sessionId,
    "stopReason": $result.stopReason, "failure": $result.failureKind,
    "error": result.errorMessage, "errorCode": result.errorCode,
    "outputBytes": result.outputBytes}))
  if not request.onEvent.isNil:
    request.onEvent(AgentStreamEvent(kind: agentEventStatus,
      text: "ACP session " & result.sessionId & ": " & $result.failureKind))
  writeFile(result.lastMessageFile, result.lastMessage)
  saveSessionRecord(request, result.sessionId)

proc runInConversation*(conversation: var AgentConversation,
    request: AgentRunRequest): AgentRunResult =
  ## Lazily open a native conversation and reuse it for compatible turns.
  try:
    if conversation.isNil or conversation.closed:
      conversation = openConversation(request)
    result = conversation.runTurn(request)
  except AcpError as error:
    conversation.close()
    result = AgentRunResult(exitCode: 1, attempt: max(request.attempt, 1),
      attemptCount: 1, errorMessage: error.msg, timeoutKind: "none",
      acpAgent: request.acpAgent, backend: request.harness)
    if error of AcpRpcError:
      let rpc = cast[ref AcpRpcError](error)
      result.failureKind = failureRpc
      result.errorCode = rpc.code
      result.errorData = rpc.data
    elif error of AcpProtocolError: result.failureKind = failureProtocol
    elif error of AcpTimeoutError:
      result.failureKind = failureTimeout
      result.timeoutKind = "setup"
    else: result.failureKind = failureTransport
