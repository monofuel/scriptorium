import
  std/[json, monotimes, os, osproc, posix, streams, strformat, strutils, times],
  ./[common, logging, prompt_catalog]

const
  DefaultGrokBuildBinary = "grok"
  DefaultTicketId = "adhoc"
  DefaultAttempt = 1
  DefaultLogRoot = ".scriptorium/logs"
  DefaultPollIntervalMs = 100
  DefaultMaxAttempts = 1
  DefaultNoOutputTimeoutMs = 0
  DefaultHardTimeoutMs = 0
  DefaultHeartbeatIntervalMs = 0
  OutputChunkSize = 4096
  ContinuationTailChars = 1200
  ToolArgSummaryMaxLen = 80
  AcpProtocolVersion = 1
  ScriptoriumMcpServerName = "scriptorium"

type
  GrokBuildStreamEventKind* = enum
    grokBuildEventHeartbeat = "heartbeat"
    grokBuildEventReasoning = "reasoning"
    grokBuildEventTool = "tool"
    grokBuildEventStatus = "status"
    grokBuildEventMessage = "message"

  GrokBuildStreamEvent* = object
    kind*: GrokBuildStreamEventKind
    text*: string
    rawLine*: string

  GrokBuildEventHandler* = proc(event: GrokBuildStreamEvent)

  GrokBuildTimeoutKind* = enum
    grokBuildTimeoutNone = "none"
    grokBuildTimeoutNoOutput = "no-output"
    grokBuildTimeoutHard = "hard"
    grokBuildTimeoutProgress = "progress"

  GrokBuildRunRequest* = object
    prompt*: string
    workingDir*: string
    model*: string
    reasoningEffort*: string
    mcpEndpoint*: string
    ticketId*: string
    attempt*: int
    grokBuildBinary*: string
    logRoot*: string
    noOutputTimeoutMs*: int
    hardTimeoutMs*: int
    progressTimeoutMs*: int
    heartbeatIntervalMs*: int
    onEvent*: GrokBuildEventHandler
    maxAttempts*: int
    continuationPrompt*: string
    continuationPromptBuilder*: ContinuationPromptBuilder

  GrokBuildRunResult* = object
    command*: seq[string]
    exitCode*: int
    attempt*: int
    attemptCount*: int
    stdout*: string
    logFile*: string
    lastMessageFile*: string
    lastMessage*: string
    timeoutKind*: GrokBuildTimeoutKind

proc sanitizePathSegment(value: string): string =
  ## Sanitize a string so it can safely be used as a path segment.
  if value.len == 0:
    return DefaultTicketId

  result = ""
  for ch in value:
    if ch in {'a'..'z', 'A'..'Z', '0'..'9', '-', '_'}:
      result.add(ch)
    elif ch in {'/', '\\', ' '}:
      result.add('-')

  if result.len == 0:
    result = DefaultTicketId

proc truncateTail(value: string, maxChars: int): string =
  ## Return at most maxChars from the end of value.
  if maxChars < 1:
    result = ""
  elif value.len <= maxChars:
    result = value
  else:
    result = value[(value.len - maxChars)..^1]

proc resolveAttemptBase(request: GrokBuildRunRequest): int =
  ## Resolve the base attempt number for the current run.
  if request.attempt > 0: request.attempt
  else: DefaultAttempt

proc resolveMaxAttempts(request: GrokBuildRunRequest): int =
  ## Resolve how many attempts are allowed for the current run.
  if request.maxAttempts > 0: request.maxAttempts
  else: DefaultMaxAttempts

proc resolveNoOutputTimeoutMs(request: GrokBuildRunRequest): int =
  ## Resolve the no-output watchdog timeout in milliseconds.
  if request.noOutputTimeoutMs > 0: request.noOutputTimeoutMs
  else: DefaultNoOutputTimeoutMs

proc resolveHardTimeoutMs(request: GrokBuildRunRequest): int =
  ## Resolve the hard watchdog timeout in milliseconds.
  if request.hardTimeoutMs > 0: request.hardTimeoutMs
  else: DefaultHardTimeoutMs

proc resolveHeartbeatIntervalMs(request: GrokBuildRunRequest): int =
  ## Resolve how often heartbeat events should be emitted in milliseconds.
  if request.heartbeatIntervalMs > 0: request.heartbeatIntervalMs
  else: DefaultHeartbeatIntervalMs

proc elapsedMs(since: MonoTime): int64 =
  ## Return elapsed milliseconds from since until now.
  result = (getMonoTime() - since).inMilliseconds

proc waitForReadable(fd: cint, timeoutMs: int): bool =
  ## Wait until fd has readable data or the timeout expires.
  while true:
    var readSet: TFdSet
    FD_ZERO(readSet)
    FD_SET(fd, readSet)

    let tvSec = timeoutMs div 1000
    let tvUsec = (timeoutMs mod 1000) * 1000
    var timeout = Timeval(
      tv_sec: posix.Time(tvSec),
      tv_usec: posix.Suseconds(tvUsec),
    )

    let selectRc = select(fd + 1, addr readSet, nil, nil, addr timeout)
    if selectRc < 0:
      if osLastError() == OSErrorCode(EINTR):
        continue
      raise newException(IOError, &"select failed for grok-build output fd {fd}")
    result = selectRc > 0 and FD_ISSET(fd, readSet) != 0
    break

proc readOutputChunk(fd: cint): tuple[data: string, eof: bool] =
  ## Read one available output chunk from fd.
  var buffer = newString(OutputChunkSize)
  while true:
    let bytesRead = posix.read(fd, addr buffer[0], buffer.len)
    if bytesRead < 0:
      if osLastError() == OSErrorCode(EINTR):
        continue
      raise newException(IOError, &"read failed for grok-build output fd {fd}")
    if bytesRead == 0:
      result = ("", true)
    else:
      buffer.setLen(bytesRead)
      result = (buffer, false)
    break

proc buildGrokBuildCmdArgs*(request: GrokBuildRunRequest): seq[string] =
  ## Build the grok agent stdio argument list for ACP execution.
  if request.model.len == 0:
    raise newException(ValueError, "model is required")

  result = @[
    "agent",
    "--always-approve",
    "--model",
    request.model,
  ]

  let cleanEffort = request.reasoningEffort.strip()
  if cleanEffort.len > 0:
    result.add("--reasoning-effort")
    result.add(cleanEffort)

  result.add("stdio")

proc buildGrokBuildMcpServers*(endpoint: string): JsonNode =
  ## Build the session/new mcpServers array for the scriptorium HTTP MCP endpoint.
  ## HTTP MCP servers require type, name, url, and headers (empty array is valid).
  result = newJArray()
  let cleanEndpoint = endpoint.strip()
  if cleanEndpoint.len == 0:
    return

  var endpointBase = cleanEndpoint
  while endpointBase.endsWith("/"):
    endpointBase.setLen(endpointBase.len - 1)
  if endpointBase.len == 0:
    return

  let mcpUrl = endpointBase & "/mcp"
  result.add(%*{
    "type": "http",
    "name": ScriptoriumMcpServerName,
    "url": mcpUrl,
    "headers": newJArray(),
  })

proc buildAcpInitializeParams*(): JsonNode =
  ## Build initialize params for the ACP handshake.
  result = %*{
    "protocolVersion": AcpProtocolVersion,
    "clientCapabilities": {
      "fs": {
        "readTextFile": true,
        "writeTextFile": true,
      },
      "terminal": false,
    },
    "clientInfo": {
      "name": "scriptorium",
      "version": "0.1.0",
    },
  }

proc buildAcpSessionNewParams*(workingDir: string, mcpEndpoint: string): JsonNode =
  ## Build session/new params including optional scriptorium MCP servers.
  result = %*{
    "cwd": workingDir,
    "mcpServers": buildGrokBuildMcpServers(mcpEndpoint),
    "_meta": {
      "yoloMode": true,
    },
  }

proc buildAcpPromptParams*(sessionId: string, prompt: string): JsonNode =
  ## Build session/prompt params with a single text content block.
  result = %*{
    "sessionId": sessionId,
    "prompt": [
      {
        "type": "text",
        "text": prompt,
      },
    ],
  }

proc extractToolArgSummary(rawInput: JsonNode): string =
  ## Extract a short argument summary from a tool_call rawInput object.
  if rawInput.isNil or rawInput.kind != JObject:
    return ""
  for key in ["path", "file_path", "filename", "file", "command", "query", "url"]:
    let val = rawInput.getOrDefault(key).getStr("")
    if val.len > 0:
      return val[0 ..< min(val.len, ToolArgSummaryMaxLen)]
  return ""

proc buildGrokBuildStreamEventFromUpdate*(update: JsonNode, rawLine: string): GrokBuildStreamEvent =
  ## Map one ACP sessionUpdate object into a normalized stream event.
  result = GrokBuildStreamEvent(kind: grokBuildEventStatus, text: "", rawLine: rawLine)
  if update.isNil or update.kind != JObject:
    return

  let kind = update.getOrDefault("sessionUpdate").getStr("").strip()
  case kind
  of "agent_thought_chunk":
    let text = update.getOrDefault("content").getOrDefault("text").getStr("")
    result = GrokBuildStreamEvent(
      kind: grokBuildEventReasoning,
      text: text,
      rawLine: rawLine,
    )
  of "agent_message_chunk":
    let text = update.getOrDefault("content").getOrDefault("text").getStr("")
    result = GrokBuildStreamEvent(
      kind: grokBuildEventMessage,
      text: text,
      rawLine: rawLine,
    )
  of "tool_call":
    let title = update.getOrDefault("title").getStr("")
    let toolName = update.getOrDefault("toolName").getStr("")
    let name = if title.len > 0: title elif toolName.len > 0: toolName else: "tool"
    let summary = extractToolArgSummary(update.getOrDefault("rawInput"))
    let text = if summary.len > 0: name & " " & summary else: name
    result = GrokBuildStreamEvent(
      kind: grokBuildEventTool,
      text: text,
      rawLine: rawLine,
    )
  of "tool_call_update":
    let status = update.getOrDefault("status").getStr("")
    result = GrokBuildStreamEvent(
      kind: grokBuildEventStatus,
      text: status,
      rawLine: rawLine,
    )
  else:
    result = GrokBuildStreamEvent(
      kind: grokBuildEventStatus,
      text: kind,
      rawLine: rawLine,
    )

proc buildGrokBuildStreamEvent*(line: string): GrokBuildStreamEvent =
  ## Parse one ACP stdout line into a stream event when it is a session/update.
  result = GrokBuildStreamEvent(kind: grokBuildEventStatus, text: "", rawLine: line)
  if line.len == 0:
    return

  var parsed: JsonNode
  try:
    parsed = parseJson(line)
  except JsonParsingError:
    return

  if parsed.kind != JObject:
    return

  let methodName = parsed.getOrDefault("method").getStr("")
  if methodName != "session/update":
    if methodName.len > 0:
      result = GrokBuildStreamEvent(
        kind: grokBuildEventStatus,
        text: methodName,
        rawLine: line,
      )
    return

  let update = parsed.getOrDefault("params").getOrDefault("update")
  result = buildGrokBuildStreamEventFromUpdate(update, line)

proc emitGrokBuildEvent(onEvent: GrokBuildEventHandler, event: GrokBuildStreamEvent) =
  ## Emit one stream event when callbacks are configured.
  if onEvent.isNil:
    return
  if event.kind == grokBuildEventStatus and event.text.len == 0:
    return
  if event.kind == grokBuildEventMessage and event.text.len == 0:
    return
  if event.kind == grokBuildEventReasoning and event.text.len == 0:
    return
  onEvent(event)

proc buildContinuationPrompt(
  originalPrompt: string,
  previousResult: GrokBuildRunResult,
  customContinuationPrompt: string,
  builder: ContinuationPromptBuilder = nil,
  workingDir: string = "",
): string =
  ## Build the prompt text for a retry attempt after a failed run.
  let summarySource = if previousResult.lastMessage.len > 0: previousResult.lastMessage else: previousResult.stdout
  let summaryTail = truncateTail(summarySource, ContinuationTailChars).strip()
  let builtText = if not builder.isNil and workingDir.len > 0: builder(workingDir) else: ""
  let continuationText = if builtText.len > 0:
      builtText.strip()
    elif customContinuationPrompt.len > 0:
      customContinuationPrompt.strip()
    else:
      CodexRetryDefaultContinuationText.strip()

  let retryPrompt = renderPromptTemplate(
    CodexRetryContinuationTemplate,
    [
      (name: "ATTEMPT", value: $previousResult.attempt),
      (name: "EXIT_CODE", value: $previousResult.exitCode),
      (name: "TIMEOUT_KIND", value: $previousResult.timeoutKind),
      (name: "SUMMARY_TAIL", value: summaryTail),
      (name: "CONTINUATION_TEXT", value: continuationText),
    ],
  )
  result = originalPrompt.strip() & "\n\n" & retryPrompt

type
  AcpLineKind = enum
    acpLineIgnore
    acpLineResponse
    acpLineError
    acpLineUpdate

  AcpParsedLine = object
    kind: AcpLineKind
    id: int
    resultNode: JsonNode
    errorMessage: string
    event: GrokBuildStreamEvent
    rawLine: string

proc parseAcpLine(line: string): AcpParsedLine =
  ## Classify one stdout line as a JSON-RPC response, error, update, or noise.
  result = AcpParsedLine(kind: acpLineIgnore, rawLine: line)
  if line.len == 0:
    return

  var parsed: JsonNode
  try:
    parsed = parseJson(line)
  except JsonParsingError:
    return

  if parsed.kind != JObject:
    return

  if parsed.hasKey("id") and parsed["id"].kind == JInt:
    result.id = parsed["id"].getInt()
    if parsed.hasKey("error"):
      result.kind = acpLineError
      let err = parsed["error"]
      let msg = err.getOrDefault("message").getStr("error")
      let data = err.getOrDefault("data")
      if data.kind == JString:
        result.errorMessage = msg & ": " & data.getStr()
      else:
        result.errorMessage = msg
      return
    if parsed.hasKey("result"):
      result.kind = acpLineResponse
      result.resultNode = parsed["result"]
      return

  let methodName = parsed.getOrDefault("method").getStr("")
  if methodName == "session/update":
    result.kind = acpLineUpdate
    let update = parsed.getOrDefault("params").getOrDefault("update")
    result.event = buildGrokBuildStreamEventFromUpdate(update, line)
    return

  if methodName.len > 0:
    result.kind = acpLineUpdate
    result.event = GrokBuildStreamEvent(
      kind: grokBuildEventStatus,
      text: methodName,
      rawLine: line,
    )

proc writeAcpRequest(inputStream: Stream, id: int, methodName: string, params: JsonNode) =
  ## Write one JSON-RPC request line to the agent stdin stream.
  let payload = %*{
    "jsonrpc": "2.0",
    "id": id,
    "method": methodName,
    "params": params,
  }
  inputStream.write($payload & "\n")
  inputStream.flush()

proc runGrokBuildAttempt(request: GrokBuildRunRequest, prompt: string, attemptValue: int): GrokBuildRunResult =
  ## Run one grok ACP agent session and capture streamed output, logs, and timeouts.
  if request.workingDir.len == 0:
    raise newException(ValueError, "workingDir is required")
  if request.model.len == 0:
    raise newException(ValueError, "model is required")

  let ticketValue = if request.ticketId.len > 0: request.ticketId else: DefaultTicketId
  let logRoot = if request.logRoot.len > 0: request.logRoot else: request.workingDir / DefaultLogRoot
  let grokBinary = if request.grokBuildBinary.len > 0: request.grokBuildBinary else: DefaultGrokBuildBinary
  let noOutputTimeoutMs = resolveNoOutputTimeoutMs(request)
  let hardTimeoutMs = resolveHardTimeoutMs(request)
  let heartbeatIntervalMs = resolveHeartbeatIntervalMs(request)
  let progressTimeoutMs = if request.progressTimeoutMs > 0: request.progressTimeoutMs else: 0

  let ticketDir = logRoot / sanitizePathSegment(ticketValue)
  createDir(ticketDir)

  let attemptPrefix = &"attempt-{attemptValue:02d}"
  let logFilePath = ticketDir / (attemptPrefix & ".jsonl")
  let lastMessagePath = ticketDir / (attemptPrefix & ".last_message.txt")
  let args = buildGrokBuildCmdArgs(request)

  var runResult = GrokBuildRunResult(
    command: @[grokBinary] & args,
    attempt: attemptValue,
    attemptCount: 1,
    timeoutKind: grokBuildTimeoutNone,
    logFile: logFilePath,
    lastMessageFile: lastMessagePath,
    stdout: "",
    lastMessage: "",
    exitCode: 1,
  )

  let fullCmd = runResult.command.join(" ")
  logDebug("grok-build command: " & fullCmd)

  let logFile = open(logFilePath, fmWrite)
  defer:
    logFile.close()

  # Keep stderr separate so JSON-RPC on stdout stays clean.
  let process = startProcess(
    grokBinary,
    workingDir = request.workingDir,
    args = args,
    options = {poUsePath},
  )
  defer:
    process.close()

  let inputStream = process.inputStream
  let outputFd = cint(process.outputHandle)
  let startTime = getMonoTime()
  var lastOutputTime = startTime
  var lastToolTime = startTime
  var lastHeartbeatTime = startTime
  var streamClosed = false
  var stopRequested = false
  var pendingLine = ""
  var messageText = ""
  var sessionId = ""
  var nextRequestId = 1
  var waitingForId = 0
  var waitingPhase = "initialize"
  var acpError = ""
  var promptCompleted = false
  var stdoutBuf = ""

  var wrappedOnEvent: GrokBuildEventHandler = nil
  if not request.onEvent.isNil:
    wrappedOnEvent = proc(event: GrokBuildStreamEvent) =
      if event.kind == grokBuildEventTool:
        lastToolTime = getMonoTime()
      request.onEvent(event)

  proc handleCompleteLine(line: string) =
    ## Process one complete ACP stdout line.
    logFile.write(line & "\n")
    logFile.flushFile()
    stdoutBuf.add(line)
    stdoutBuf.add("\n")
    lastOutputTime = getMonoTime()
    lastHeartbeatTime = lastOutputTime

    let parsed = parseAcpLine(line)
    case parsed.kind
    of acpLineIgnore:
      discard
    of acpLineUpdate:
      if parsed.event.kind == grokBuildEventMessage:
        messageText.add(parsed.event.text)
      emitGrokBuildEvent(wrappedOnEvent, parsed.event)
    of acpLineError:
      if waitingForId > 0 and parsed.id == waitingForId:
        acpError = parsed.errorMessage
        waitingForId = 0
      else:
        emitGrokBuildEvent(
          wrappedOnEvent,
          GrokBuildStreamEvent(
            kind: grokBuildEventStatus,
            text: "error: " & parsed.errorMessage,
            rawLine: line,
          ),
        )
    of acpLineResponse:
      if waitingForId > 0 and parsed.id == waitingForId:
        if waitingPhase == "initialize":
          waitingPhase = "session/new"
          waitingForId = nextRequestId
          inc nextRequestId
          writeAcpRequest(
            inputStream,
            waitingForId,
            "session/new",
            buildAcpSessionNewParams(request.workingDir, request.mcpEndpoint),
          )
        elif waitingPhase == "session/new":
          sessionId = parsed.resultNode.getOrDefault("sessionId").getStr("")
          if sessionId.len == 0:
            acpError = "session/new response missing sessionId"
            waitingForId = 0
          else:
            waitingPhase = "session/prompt"
            waitingForId = nextRequestId
            inc nextRequestId
            writeAcpRequest(
              inputStream,
              waitingForId,
              "session/prompt",
              buildAcpPromptParams(sessionId, prompt),
            )
        elif waitingPhase == "session/prompt":
          promptCompleted = true
          waitingForId = 0
          waitingPhase = "done"
          let stopReason = parsed.resultNode.getOrDefault("stopReason").getStr("")
          emitGrokBuildEvent(
            wrappedOnEvent,
            GrokBuildStreamEvent(
              kind: grokBuildEventStatus,
              text: "stopReason=" & stopReason,
              rawLine: line,
            ),
          )
        else:
          waitingForId = 0

  # Kick off the ACP handshake.
  waitingForId = nextRequestId
  inc nextRequestId
  writeAcpRequest(inputStream, waitingForId, "initialize", buildAcpInitializeParams())

  while not stopRequested:
    if promptCompleted or acpError.len > 0:
      break

    if heartbeatIntervalMs > 0 and not wrappedOnEvent.isNil:
      let now = getMonoTime()
      if elapsedMs(lastOutputTime) >= heartbeatIntervalMs.int64 and
          elapsedMs(lastHeartbeatTime) >= heartbeatIntervalMs.int64:
        emitGrokBuildEvent(
          wrappedOnEvent,
          GrokBuildStreamEvent(
            kind: grokBuildEventHeartbeat,
            text: "still working",
            rawLine: "",
          ),
        )
        lastHeartbeatTime = now

    if hardTimeoutMs > 0 and elapsedMs(startTime) >= hardTimeoutMs.int64:
      runResult.timeoutKind = grokBuildTimeoutHard
      let elapsedSec = elapsedMs(startTime) div 1000
      logWarn(&"agent {ticketValue}: killing process (hard timeout after {elapsedSec}s)")
      process.kill()
      stopRequested = true
    if noOutputTimeoutMs > 0 and elapsedMs(lastOutputTime) >= noOutputTimeoutMs.int64:
      runResult.timeoutKind = grokBuildTimeoutNoOutput
      let silentSec = elapsedMs(lastOutputTime) div 1000
      logWarn(&"agent {ticketValue}: killing process (no output for {silentSec}s)")
      process.kill()
      stopRequested = true
    if progressTimeoutMs > 0 and elapsedMs(lastToolTime) >= progressTimeoutMs.int64:
      if elapsedMs(lastOutputTime) < elapsedMs(lastToolTime):
        runResult.timeoutKind = grokBuildTimeoutProgress
        let stallSec = elapsedMs(lastToolTime) div 1000
        logWarn(&"agent {ticketValue}: killing process (no tool progress for {stallSec}s)")
        process.kill()
        stopRequested = true

    if not streamClosed and waitForReadable(outputFd, DefaultPollIntervalMs):
      let (chunk, chunkEof) = readOutputChunk(outputFd)
      if chunkEof:
        streamClosed = true
      elif chunk.len > 0:
        let combined = pendingLine & chunk
        var lineStart = 0
        for index in 0..<combined.len:
          if combined[index] == '\n':
            let line = combined[lineStart..<index].strip(chars = {'\r', '\n'})
            if line.len > 0:
              handleCompleteLine(line)
            lineStart = index + 1
        if lineStart < combined.len:
          pendingLine = combined[lineStart..^1]
        else:
          pendingLine = ""
    elif streamClosed and process.peekExitCode() != -1:
      break

    if process.peekExitCode() != -1 and not streamClosed:
      if not waitForReadable(outputFd, 0):
        streamClosed = true

  if pendingLine.strip().len > 0 and not stopRequested:
    handleCompleteLine(pendingLine.strip())
    pendingLine = ""

  # End the session process promptly once the prompt completes or fails.
  if process.peekExitCode() == -1:
    process.kill()

  runResult.exitCode = process.waitForExit()
  if promptCompleted and runResult.timeoutKind == grokBuildTimeoutNone and acpError.len == 0:
    runResult.exitCode = 0
  elif acpError.len > 0:
    runResult.exitCode = 1
    emitGrokBuildEvent(
      wrappedOnEvent,
      GrokBuildStreamEvent(
        kind: grokBuildEventStatus,
        text: "acp error: " & acpError,
        rawLine: "",
      ),
    )

  runResult.stdout = stdoutBuf
  runResult.lastMessage = messageText
  if runResult.lastMessage.len > 0:
    writeFile(lastMessagePath, runResult.lastMessage)

  result = runResult

proc runGrokBuild*(request: GrokBuildRunRequest): GrokBuildRunResult =
  ## Run grok-build via ACP with optional bounded retries and continuation prompts.
  if request.workingDir.len == 0:
    raise newException(ValueError, "workingDir is required")
  if request.model.len == 0:
    raise newException(ValueError, "model is required")

  let baseAttempt = resolveAttemptBase(request)
  let maxAttempts = resolveMaxAttempts(request)
  let originalPrompt = request.prompt
  var prompt = originalPrompt
  var attemptsUsed = 0

  while attemptsUsed < maxAttempts:
    let attemptValue = baseAttempt + attemptsUsed
    result = runGrokBuildAttempt(request, prompt, attemptValue)
    inc attemptsUsed
    result.attemptCount = attemptsUsed

    let completed = result.exitCode == 0 and result.timeoutKind == grokBuildTimeoutNone
    if completed:
      break

    if attemptsUsed < maxAttempts:
      prompt = buildContinuationPrompt(
        originalPrompt,
        result,
        request.continuationPrompt,
        request.continuationPromptBuilder,
        request.workingDir,
      )
