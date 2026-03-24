import
  std/[envvars, json, monotimes, os, osproc, posix, streams, strformat, strtabs, strutils, times],
  ./[common, config, logging, prompt_catalog]

const
  DefaultClaudeCodeBinary = "claude"
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

type
  ClaudeCodeStreamEventKind* = enum
    claudeCodeEventHeartbeat = "heartbeat"
    claudeCodeEventReasoning = "reasoning"
    claudeCodeEventTool = "tool"
    claudeCodeEventStatus = "status"
    claudeCodeEventMessage = "message"

  ClaudeCodeStreamEvent* = object
    kind*: ClaudeCodeStreamEventKind
    text*: string
    rawLine*: string

  ClaudeCodeEventHandler* = proc(event: ClaudeCodeStreamEvent)

  ClaudeCodeTimeoutKind* = enum
    claudeCodeTimeoutNone = "none"
    claudeCodeTimeoutNoOutput = "no-output"
    claudeCodeTimeoutHard = "hard"
    claudeCodeTimeoutProgress = "progress"

  ClaudeCodeRunRequest* = object
    prompt*: string
    workingDir*: string
    model*: string
    reasoningEffort*: string
    mcpEndpoint*: string
    ticketId*: string
    attempt*: int
    claudeCodeBinary*: string
    logRoot*: string
    noOutputTimeoutMs*: int
    hardTimeoutMs*: int
    progressTimeoutMs*: int
    heartbeatIntervalMs*: int
    onEvent*: ClaudeCodeEventHandler
    maxAttempts*: int
    continuationPrompt*: string
    continuationPromptBuilder*: ContinuationPromptBuilder

  ClaudeCodeRunResult* = object
    command*: seq[string]
    exitCode*: int
    attempt*: int
    attemptCount*: int
    stdout*: string
    logFile*: string
    lastMessageFile*: string
    lastMessage*: string
    timeoutKind*: ClaudeCodeTimeoutKind

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

proc resolveAttemptBase(request: ClaudeCodeRunRequest): int =
  ## Resolve the base attempt number for the current run.
  if request.attempt > 0: request.attempt
  else: DefaultAttempt

proc resolveMaxAttempts(request: ClaudeCodeRunRequest): int =
  ## Resolve how many attempts are allowed for the current run.
  if request.maxAttempts > 0: request.maxAttempts
  else: DefaultMaxAttempts

proc resolveNoOutputTimeoutMs(request: ClaudeCodeRunRequest): int =
  ## Resolve the no-output watchdog timeout in milliseconds.
  if request.noOutputTimeoutMs > 0: request.noOutputTimeoutMs
  else: DefaultNoOutputTimeoutMs

proc resolveHardTimeoutMs(request: ClaudeCodeRunRequest): int =
  ## Resolve the hard watchdog timeout in milliseconds.
  if request.hardTimeoutMs > 0: request.hardTimeoutMs
  else: DefaultHardTimeoutMs

proc resolveHeartbeatIntervalMs(request: ClaudeCodeRunRequest): int =
  ## Resolve how often heartbeat events should be emitted in milliseconds.
  if request.heartbeatIntervalMs > 0: request.heartbeatIntervalMs
  else: DefaultHeartbeatIntervalMs

proc normalizeReasoningEffort(value: string): string =
  ## Normalize one reasoning effort string to a supported Claude Code value.
  let clean = value.strip().toLowerAscii()
  if clean.len == 0:
    return ""
  case clean
  of "low", "medium", "high":
    result = clean
  else:
    raise newException(ValueError, &"unsupported reasoning effort for claude-code: {clean}")

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
      raise newException(IOError, &"select failed for claude-code output fd {fd}")
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
      raise newException(IOError, &"read failed for claude-code output fd {fd}")
    if bytesRead == 0:
      result = ("", true)
    else:
      buffer.setLen(bytesRead)
      result = (buffer, false)
    break

proc buildMcpConfigJson*(endpoint: string): string =
  ## Build the MCP server configuration JSON string for Claude Code.
  let cleanEndpoint = endpoint.strip()
  if cleanEndpoint.len == 0:
    return ""

  var endpointBase = cleanEndpoint
  while endpointBase.endsWith("/"):
    endpointBase.setLen(endpointBase.len - 1)

  if endpointBase.len == 0:
    return ""

  let mcpUrl = endpointBase & "/mcp"
  let configObj = %* {
    "mcpServers": {
      "scriptorium": {
        "type": "http",
        "url": mcpUrl
      }
    }
  }
  result = $configObj

proc buildClaudeCodeExecArgs*(request: ClaudeCodeRunRequest): seq[string] =
  ## Build the Claude Code argument list for non-interactive execution.
  ## Applies resolveModel() so Bedrock model IDs are used when CLAUDE_CODE_USE_BEDROCK is set.
  if request.model.len == 0:
    raise newException(ValueError, "model is required")

  let resolvedModel = resolveModel(request.model)
  result = @[
    "--print",
    "--output-format", "stream-json",
    "--verbose",
    "--dangerously-skip-permissions",
    "--model", resolvedModel,
  ]

  let reasoningEffort = normalizeReasoningEffort(request.reasoningEffort)
  if reasoningEffort.len > 0:
    result.add("--effort")
    result.add(reasoningEffort)

  let mcpConfig = buildMcpConfigJson(request.mcpEndpoint)
  if mcpConfig.len > 0:
    result.add("--mcp-config")
    result.add(mcpConfig)

proc extractToolArgSummary(input: JsonNode): string =
  ## Extract a short argument summary from a tool_use input object.
  if input.isNil or input.kind != JObject:
    return ""
  for key in ["file_path", "path", "filename", "file"]:
    let val = input.getOrDefault(key).getStr("")
    if val.len > 0:
      return val[0 ..< min(val.len, ToolArgSummaryMaxLen)]
  let cmd = input.getOrDefault("command").getStr("")
  if cmd.len > 0:
    return cmd[0 ..< min(cmd.len, ToolArgSummaryMaxLen)]
  return ""

proc buildClaudeCodeStreamEvent*(line: string): ClaudeCodeStreamEvent =
  ## Parse one Claude Code stream-json line into a normalized stream event.
  result = ClaudeCodeStreamEvent(kind: claudeCodeEventStatus, text: "", rawLine: line)
  if line.len == 0:
    return

  var parsed: JsonNode
  try:
    parsed = parseJson(line)
  except JsonParsingError:
    return

  let eventType = parsed.getOrDefault("type").getStr("")

  case eventType
  of "system":
    let subtype = parsed.getOrDefault("subtype").getStr("")
    let model = parsed.getOrDefault("model").getStr("")
    let statusText = if model.len > 0: "init (" & model & ")" else: subtype
    result = ClaudeCodeStreamEvent(
      kind: claudeCodeEventStatus,
      text: statusText,
      rawLine: line,
    )

  of "assistant":
    let message = parsed.getOrDefault("message")
    if message.isNil or message.kind != JObject:
      return

    let content = message.getOrDefault("content")
    if content.isNil or content.kind != JArray or content.len == 0:
      return

    let firstBlock = content[0]
    let blockType = firstBlock.getOrDefault("type").getStr("")

    case blockType
    of "thinking":
      let thinking = firstBlock.getOrDefault("thinking").getStr("")
      result = ClaudeCodeStreamEvent(
        kind: claudeCodeEventReasoning,
        text: thinking,
        rawLine: line,
      )

    of "tool_use":
      let toolName = firstBlock.getOrDefault("name").getStr("")
      let input = firstBlock.getOrDefault("input")
      let argSummary = extractToolArgSummary(input)
      let toolText = if argSummary.len > 0: toolName & " " & argSummary else: toolName
      result = ClaudeCodeStreamEvent(
        kind: claudeCodeEventTool,
        text: toolText,
        rawLine: line,
      )

    of "text":
      let text = firstBlock.getOrDefault("text").getStr("")
      result = ClaudeCodeStreamEvent(
        kind: claudeCodeEventMessage,
        text: text,
        rawLine: line,
      )

    else:
      discard

  of "user":
    let message = parsed.getOrDefault("message")
    if message.isNil or message.kind != JObject:
      return

    let content = message.getOrDefault("content")
    if content.isNil or content.kind != JArray or content.len == 0:
      return

    let firstBlock = content[0]
    let blockType = firstBlock.getOrDefault("type").getStr("")

    if blockType == "tool_result":
      let toolUseId = firstBlock.getOrDefault("tool_use_id").getStr("")
      let isError = firstBlock.getOrDefault("is_error").getBool(false)
      let stateText = if isError: "error" else: "completed"
      let displayText = if toolUseId.len > 0: toolUseId & " (" & stateText & ")"
                        else: "tool_result (" & stateText & ")"
      result = ClaudeCodeStreamEvent(
        kind: claudeCodeEventTool,
        text: displayText,
        rawLine: line,
      )

  of "result":
    let subtype = parsed.getOrDefault("subtype").getStr("")
    let isError = parsed.getOrDefault("is_error").getBool(false)
    let stopReason = parsed.getOrDefault("stop_reason").getStr("")
    let stateText = if isError: "error" else: subtype
    let displayText = if stopReason.len > 0: stateText & " (" & stopReason & ")"
                      else: stateText
    result = ClaudeCodeStreamEvent(
      kind: claudeCodeEventStatus,
      text: displayText,
      rawLine: line,
    )

  else:
    discard

proc extractLastMessageFromStream*(output: string): string =
  ## Extract the final assistant text message from accumulated stream output.
  for rawLine in output.splitLines():
    let line = rawLine.strip()
    if line.len == 0:
      continue

    var parsed: JsonNode
    try:
      parsed = parseJson(line)
    except JsonParsingError:
      continue

    let eventType = parsed.getOrDefault("type").getStr("")

    if eventType == "result":
      let resultText = parsed.getOrDefault("result").getStr("")
      if resultText.len > 0:
        result = resultText
      continue

    if eventType == "assistant":
      let message = parsed.getOrDefault("message")
      if message.isNil or message.kind != JObject:
        continue

      let content = message.getOrDefault("content")
      if content.isNil or content.kind != JArray or content.len == 0:
        continue

      let firstBlock = content[0]
      let blockType = firstBlock.getOrDefault("type").getStr("")
      if blockType == "text":
        let text = firstBlock.getOrDefault("text").getStr("")
        if text.len > 0:
          result = text

proc emitClaudeCodeEvent(onEvent: ClaudeCodeEventHandler, event: ClaudeCodeStreamEvent) =
  ## Emit one Claude Code stream event when callbacks are configured.
  if onEvent.isNil:
    return
  if event.kind == claudeCodeEventStatus and event.text.len == 0:
    return
  if event.kind == claudeCodeEventMessage and event.text.len == 0:
    return
  onEvent(event)

proc emitClaudeCodeEventsFromChunk(
  onEvent: ClaudeCodeEventHandler,
  pendingLine: var string,
  chunk: string,
) =
  ## Parse one output chunk into JSONL lines and emit normalized events.
  let combined = pendingLine & chunk
  var lineStart = 0
  for index in 0..<combined.len:
    if combined[index] == '\n':
      let line = combined[lineStart..<index].strip()
      if line.len > 0:
        emitClaudeCodeEvent(onEvent, buildClaudeCodeStreamEvent(line))
      lineStart = index + 1

  if lineStart < combined.len:
    pendingLine = combined[lineStart..^1]
  else:
    pendingLine = ""

proc flushPendingClaudeCodeEvents(onEvent: ClaudeCodeEventHandler, pendingLine: var string) =
  ## Emit one final event for buffered partial output when present.
  let line = pendingLine.strip()
  if line.len > 0:
    emitClaudeCodeEvent(onEvent, buildClaudeCodeStreamEvent(line))
  pendingLine = ""

proc buildContinuationPrompt(
  originalPrompt: string,
  previousResult: ClaudeCodeRunResult,
  customContinuationPrompt: string,
  builder: ContinuationPromptBuilder = nil,
  workingDir: string = "",
): string =
  ## Build the prompt text for a retry attempt after a failed run.
  let summarySource = if previousResult.lastMessage.len > 0: previousResult.lastMessage
                      else: previousResult.stdout
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

proc runClaudeCodeAttempt(request: ClaudeCodeRunRequest, prompt: string, attemptValue: int): ClaudeCodeRunResult =
  ## Run one Claude Code attempt and capture streamed output, logs, and timeout state.
  if request.workingDir.len == 0:
    raise newException(ValueError, "workingDir is required")
  if request.model.len == 0:
    raise newException(ValueError, "model is required")

  let ticketValue = if request.ticketId.len > 0: request.ticketId else: DefaultTicketId
  let logRoot = if request.logRoot.len > 0: request.logRoot else: request.workingDir / DefaultLogRoot
  let claudeBinary = if request.claudeCodeBinary.len > 0: request.claudeCodeBinary else: DefaultClaudeCodeBinary
  let noOutputTimeoutMs = resolveNoOutputTimeoutMs(request)
  let hardTimeoutMs = resolveHardTimeoutMs(request)
  let heartbeatIntervalMs = resolveHeartbeatIntervalMs(request)

  let ticketDir = logRoot / sanitizePathSegment(ticketValue)
  createDir(ticketDir)

  let attemptPrefix = &"attempt-{attemptValue:02d}"
  let logFilePath = ticketDir / (attemptPrefix & ".jsonl")
  let lastMessagePath = ticketDir / (attemptPrefix & ".last_message.txt")
  let args = buildClaudeCodeExecArgs(ClaudeCodeRunRequest(
    model: request.model,
    reasoningEffort: request.reasoningEffort,
    mcpEndpoint: request.mcpEndpoint,
  ))

  result.command = @[claudeBinary] & args
  result.attempt = attemptValue
  result.attemptCount = 1
  result.timeoutKind = claudeCodeTimeoutNone
  result.logFile = logFilePath
  result.lastMessageFile = lastMessagePath
  result.stdout = ""
  result.lastMessage = ""

  let fullCmd = result.command.join(" ")
  logDebug("claude-code command: " & fullCmd)

  let logFile = open(logFilePath, fmWrite)
  defer:
    logFile.close()

  # Build a filtered environment that removes CLAUDECODE to avoid nesting
  # protection when scriptorium itself runs inside a Claude Code session.
  var env = newStringTable()
  for key, val in envPairs():
    if key != "CLAUDECODE":
      env[key] = val

  let process = startProcess(
    claudeBinary,
    workingDir = request.workingDir,
    args = args,
    env = env,
    options = {poUsePath, poStdErrToStdOut}
  )
  defer:
    process.close()

  let inputStream = process.inputStream
  inputStream.write(prompt)
  inputStream.close()

  let outputFd = cint(process.outputHandle)
  let startTime = getMonoTime()
  var lastOutputTime = startTime
  var lastToolTime = startTime
  var lastHeartbeatTime = startTime
  var streamClosed = false
  var stopRequested = false
  var pendingLine = ""
  let progressTimeoutMs = if request.progressTimeoutMs > 0: request.progressTimeoutMs else: 0

  # Wrap onEvent to track last tool-call timestamp for progress-based stall detection.
  var wrappedOnEvent: ClaudeCodeEventHandler = nil
  if not request.onEvent.isNil:
    wrappedOnEvent = proc(event: ClaudeCodeStreamEvent) =
      if event.kind == claudeCodeEventTool:
        lastToolTime = getMonoTime()
      request.onEvent(event)

  while not stopRequested:
    if heartbeatIntervalMs > 0 and not wrappedOnEvent.isNil:
      let now = getMonoTime()
      if elapsedMs(lastOutputTime) >= heartbeatIntervalMs.int64 and elapsedMs(lastHeartbeatTime) >= heartbeatIntervalMs.int64:
        emitClaudeCodeEvent(
          wrappedOnEvent,
          ClaudeCodeStreamEvent(
            kind: claudeCodeEventHeartbeat,
            text: "still working",
            rawLine: "",
          ),
        )
        lastHeartbeatTime = now

    if hardTimeoutMs > 0 and elapsedMs(startTime) >= hardTimeoutMs.int64:
      result.timeoutKind = claudeCodeTimeoutHard
      let elapsedSec = elapsedMs(startTime) div 1000
      logWarn(&"agent {ticketValue}: killing process (hard timeout after {elapsedSec}s)")
      process.kill()
      stopRequested = true
    if noOutputTimeoutMs > 0 and elapsedMs(lastOutputTime) >= noOutputTimeoutMs.int64:
      result.timeoutKind = claudeCodeTimeoutNoOutput
      let silentSec = elapsedMs(lastOutputTime) div 1000
      logWarn(&"agent {ticketValue}: killing process (no output for {silentSec}s)")
      process.kill()
      stopRequested = true
    if progressTimeoutMs > 0 and elapsedMs(lastToolTime) >= progressTimeoutMs.int64:
      # Only fire if there has been output since the last tool call (agent is alive but not progressing).
      if elapsedMs(lastOutputTime) < elapsedMs(lastToolTime):
        result.timeoutKind = claudeCodeTimeoutProgress
        let stallSec = elapsedMs(lastToolTime) div 1000
        logWarn(&"agent {ticketValue}: killing process (no tool progress for {stallSec}s)")
        process.kill()
        stopRequested = true

    if not streamClosed and waitForReadable(outputFd, DefaultPollIntervalMs):
      let (chunk, chunkEof) = readOutputChunk(outputFd)
      if chunkEof:
        streamClosed = true
      elif chunk.len > 0:
        result.stdout.add(chunk)
        logFile.write(chunk)
        lastOutputTime = getMonoTime()
        lastHeartbeatTime = lastOutputTime
        emitClaudeCodeEventsFromChunk(wrappedOnEvent, pendingLine, chunk)
    elif streamClosed and process.peekExitCode() != -1:
      break

    if process.peekExitCode() != -1 and not streamClosed:
      if not waitForReadable(outputFd, 0):
        streamClosed = true

  result.exitCode = process.waitForExit()
  flushPendingClaudeCodeEvents(wrappedOnEvent, pendingLine)

  let extractedMessage = extractLastMessageFromStream(result.stdout)
  if extractedMessage.len > 0:
    result.lastMessage = extractedMessage
    writeFile(lastMessagePath, extractedMessage)

proc runClaudeCode*(request: ClaudeCodeRunRequest): ClaudeCodeRunResult =
  ## Run Claude Code with optional bounded retries and continuation prompts.
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
    result = runClaudeCodeAttempt(request, prompt, attemptValue)
    inc attemptsUsed
    result.attemptCount = attemptsUsed

    let completed = result.exitCode == 0 and result.timeoutKind == claudeCodeTimeoutNone
    if completed:
      break

    if attemptsUsed < maxAttempts:
      prompt = buildContinuationPrompt(originalPrompt, result, request.continuationPrompt, request.continuationPromptBuilder, request.workingDir)
