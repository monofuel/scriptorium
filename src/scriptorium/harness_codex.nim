import
  std/[monotimes, os, osproc, posix, streams, strformat, strutils, times],
  jsony,
  ./[common, logging, prompt_catalog]

const
  DefaultCodexBinary = "codex"
  DefaultCodexDeveloperInstructions = "developer_instructions=\"\""
  Gpt51CodexMiniModel = "gpt-5.1-codex-mini"
  Gpt51CodexMiniDefaultReasoningEffort = "high"
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
  CodexStreamEventKind* = enum
    codexEventHeartbeat = "heartbeat"
    codexEventReasoning = "reasoning"
    codexEventTool = "tool"
    codexEventStatus = "status"
    codexEventMessage = "message"

  CodexStreamEvent* = object
    kind*: CodexStreamEventKind
    text*: string
    rawLine*: string

  CodexEventHandler* = proc(event: CodexStreamEvent)

  CodexTimeoutKind* = enum
    codexTimeoutNone = "none"
    codexTimeoutNoOutput = "no-output"
    codexTimeoutHard = "hard"
    codexTimeoutProgress = "progress"

  CodexRunRequest* = object
    prompt*: string
    workingDir*: string
    model*: string
    reasoningEffort*: string
    mcpEndpoint*: string
    ticketId*: string
    attempt*: int
    codexBinary*: string
    skipGitRepoCheck*: bool
    logRoot*: string
    noOutputTimeoutMs*: int
    hardTimeoutMs*: int
    progressTimeoutMs*: int
    heartbeatIntervalMs*: int
    onEvent*: CodexEventHandler
    maxAttempts*: int
    continuationPrompt*: string
    continuationPromptBuilder*: ContinuationPromptBuilder

  CodexRunResult* = object
    command*: seq[string]
    exitCode*: int
    attempt*: int
    attemptCount*: int
    stdout*: string
    logFile*: string
    lastMessageFile*: string
    lastMessage*: string
    timeoutKind*: CodexTimeoutKind

  CodexJsonEventFields = object
    name: string
    toolName: string
    status: string
    state: string
    phase: string
    text: string
    message: string
    content: string
    summary: string
    delta: string
    filePath: string
    path: string
    filename: string
    file: string
    command: string

  CodexJsonEnvelope = object
    `type`: string
    name: string
    toolName: string
    status: string
    state: string
    phase: string
    text: string
    message: string
    content: string
    summary: string
    delta: string
    filePath: string
    path: string
    filename: string
    file: string
    command: string
    tool: CodexJsonEventFields
    data: CodexJsonEventFields
    event: CodexJsonEventFields

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

proc resolveAttemptBase(request: CodexRunRequest): int =
  ## Resolve the base attempt number for the current run.
  if request.attempt > 0:
    result = request.attempt
  else:
    result = DefaultAttempt

proc resolveMaxAttempts(request: CodexRunRequest): int =
  ## Resolve how many codex attempts are allowed for the current run.
  if request.maxAttempts > 0:
    result = request.maxAttempts
  else:
    result = DefaultMaxAttempts

proc resolveNoOutputTimeoutMs(request: CodexRunRequest): int =
  ## Resolve the no-output watchdog timeout in milliseconds.
  if request.noOutputTimeoutMs > 0:
    result = request.noOutputTimeoutMs
  else:
    result = DefaultNoOutputTimeoutMs

proc resolveHardTimeoutMs(request: CodexRunRequest): int =
  ## Resolve the hard watchdog timeout in milliseconds.
  if request.hardTimeoutMs > 0:
    result = request.hardTimeoutMs
  else:
    result = DefaultHardTimeoutMs

proc resolveHeartbeatIntervalMs(request: CodexRunRequest): int =
  ## Resolve how often heartbeat events should be emitted in milliseconds.
  if request.heartbeatIntervalMs > 0:
    result = request.heartbeatIntervalMs
  else:
    result = DefaultHeartbeatIntervalMs

proc normalizeReasoningEffort(value: string): string =
  ## Normalize one reasoning effort string to a supported codex value.
  let clean = value.strip().toLowerAscii()
  if clean.len == 0:
    return ""
  case clean
  of "low", "medium", "high", "xhigh":
    result = clean
  else:
    raise newException(ValueError, &"unsupported reasoning effort: {clean}")

proc resolveReasoningEffort(request: CodexRunRequest): string =
  ## Resolve the codex reasoning effort override for this request.
  result = normalizeReasoningEffort(request.reasoningEffort)
  let model = request.model.strip().toLowerAscii()
  if model == Gpt51CodexMiniModel:
    if result.len == 0 or result == "xhigh":
      result = Gpt51CodexMiniDefaultReasoningEffort

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
      raise newException(IOError, &"select failed for codex output fd {fd}")
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
      raise newException(IOError, &"read failed for codex output fd {fd}")
    if bytesRead == 0:
      result = ("", true)
    else:
      buffer.setLen(bytesRead)
      result = (buffer, false)
    break

proc buildMcpServersArgs(request: CodexRunRequest): seq[string] =
  ## Build codex -c args for MCP server configuration using separate flags.
  let cleanEndpoint = request.mcpEndpoint.strip()
  if cleanEndpoint.len == 0:
    return @[]

  var endpointBase = cleanEndpoint
  while endpointBase.endsWith("/"):
    endpointBase.setLen(endpointBase.len - 1)

  if endpointBase.len == 0:
    return @[]

  let mcpUrl = endpointBase & "/mcp"
  result = @[
    "-c", &"mcp_servers.scriptorium.url=\"{mcpUrl}\"",
    "-c", "mcp_servers.scriptorium.enabled=true",
    "-c", "mcp_servers.scriptorium.required=true",
  ]

proc buildCodexMcpListArgs*(request: CodexRunRequest): seq[string] =
  ## Build the codex argument list for `mcp list --json`.
  result = buildMcpServersArgs(request) & @["mcp", "list", "--json"]

proc buildCodexExecArgs*(request: CodexRunRequest, lastMessagePath: string): seq[string] =
  ## Build the codex exec argument list in a deterministic order.
  if request.workingDir.len == 0:
    raise newException(ValueError, "workingDir is required")
  if request.model.len == 0:
    raise newException(ValueError, "model is required")
  if lastMessagePath.len == 0:
    raise newException(ValueError, "lastMessagePath is required")

  let mcpServersArgs = buildMcpServersArgs(request)
  result = @[
    "-c",
    DefaultCodexDeveloperInstructions,
  ]
  result.add(mcpServersArgs)
  result.add(@[
    "exec",
    "--json",
    "--output-last-message",
    lastMessagePath,
    "--cd",
    request.workingDir,
    "--model",
    request.model,
    "--dangerously-bypass-approvals-and-sandbox",
  ])

  let reasoningEffort = resolveReasoningEffort(request)
  if reasoningEffort.len > 0:
    result.add("-c")
    result.add(&"model_reasoning_effort=\"{reasoningEffort}\"")

  if request.skipGitRepoCheck:
    result.add("--skip-git-repo-check")

  result.add("-")

proc buildContinuationPrompt(
  originalPrompt: string,
  previousResult: CodexRunResult,
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

proc firstNonEmpty(values: varargs[string]): string =
  ## Return the first non-empty trimmed value from values.
  for value in values:
    let trimmed = value.strip()
    if trimmed.len > 0:
      result = trimmed
      break

proc parseCodexJsonEnvelope(line: string, envelope: var CodexJsonEnvelope): bool =
  ## Parse one codex JSON line into a typed envelope.
  try:
    envelope = fromJson(line, CodexJsonEnvelope)
    result = true
  except ValueError:
    result = false

proc resolveCodexEventType(envelope: CodexJsonEnvelope): string =
  ## Resolve the normalized codex event type from one parsed envelope.
  result = firstNonEmpty(envelope.`type`).toLowerAscii()

proc resolveCodexToolName(envelope: CodexJsonEnvelope): string =
  ## Resolve the best available tool name from one parsed envelope.
  result = firstNonEmpty(
    envelope.name,
    envelope.toolName,
    envelope.tool.name,
    envelope.tool.toolName,
    envelope.data.name,
    envelope.data.toolName,
    envelope.event.name,
    envelope.event.toolName,
  )

proc resolveCodexToolState(envelope: CodexJsonEnvelope): string =
  ## Resolve the best available tool state from one parsed envelope.
  result = firstNonEmpty(
    envelope.status,
    envelope.state,
    envelope.phase,
    envelope.tool.status,
    envelope.tool.state,
    envelope.tool.phase,
    envelope.data.status,
    envelope.data.state,
    envelope.data.phase,
    envelope.event.status,
    envelope.event.state,
    envelope.event.phase,
  )

proc truncateSummary(s: string): string =
  ## Truncate a summary string to ToolArgSummaryMaxLen characters.
  s[0 ..< min(s.len, ToolArgSummaryMaxLen)]

proc resolveCodexToolArgSummary(envelope: CodexJsonEnvelope): string =
  ## Resolve a short argument summary from tool call argument fields in the envelope.
  let pathArg = firstNonEmpty(
    envelope.filePath,
    envelope.path,
    envelope.filename,
    envelope.file,
    envelope.tool.filePath,
    envelope.tool.path,
    envelope.tool.filename,
    envelope.tool.file,
    envelope.data.filePath,
    envelope.data.path,
    envelope.data.filename,
    envelope.data.file,
    envelope.event.filePath,
    envelope.event.path,
    envelope.event.filename,
    envelope.event.file,
  )
  if pathArg.len > 0:
    return truncateSummary(pathArg)
  let cmdArg = firstNonEmpty(
    envelope.command,
    envelope.tool.command,
    envelope.data.command,
    envelope.event.command,
  )
  if cmdArg.len > 0:
    return truncateSummary(cmdArg)
  return ""

proc resolveCodexReasoningText(envelope: CodexJsonEnvelope): string =
  ## Resolve the best available reasoning text from one parsed envelope.
  result = firstNonEmpty(
    envelope.summary,
    envelope.text,
    envelope.message,
    envelope.content,
    envelope.delta,
    envelope.data.summary,
    envelope.data.text,
    envelope.data.message,
    envelope.data.content,
    envelope.data.delta,
    envelope.event.summary,
    envelope.event.text,
    envelope.event.message,
    envelope.event.content,
    envelope.event.delta,
  )

proc resolveCodexMessageText(envelope: CodexJsonEnvelope): string =
  ## Resolve the best available message text from one parsed envelope.
  result = firstNonEmpty(
    envelope.text,
    envelope.message,
    envelope.content,
    envelope.delta,
    envelope.data.text,
    envelope.data.message,
    envelope.data.content,
    envelope.data.delta,
    envelope.event.text,
    envelope.event.message,
    envelope.event.content,
    envelope.event.delta,
  )

proc resolveCodexStatusValue(envelope: CodexJsonEnvelope): string =
  ## Resolve the best available status value from one parsed envelope.
  result = firstNonEmpty(
    envelope.status,
    envelope.state,
    envelope.phase,
    envelope.data.status,
    envelope.data.state,
    envelope.data.phase,
    envelope.event.status,
    envelope.event.state,
    envelope.event.phase,
  )

proc buildToolEventText(eventType: string, toolName: string, toolState: string): string =
  ## Build one user-facing tool event summary.
  if toolName.len > 0 and toolState.len > 0:
    result = toolName & " (" & toolState & ")"
  elif toolName.len > 0:
    result = toolName
  elif toolState.len > 0:
    result = eventType & " (" & toolState & ")"
  else:
    result = eventType

proc buildStatusEventText(eventType: string, statusValue: string): string =
  ## Build one user-facing status event summary.
  if statusValue.len > 0:
    result = eventType & " (" & statusValue & ")"
  else:
    result = eventType

proc buildCodexStreamEventFromEnvelope(
  line: string,
  envelope: CodexJsonEnvelope,
): CodexStreamEvent =
  ## Convert one parsed envelope into a normalized stream event.
  let eventType = resolveCodexEventType(envelope)
  result = CodexStreamEvent(kind: codexEventStatus, text: "", rawLine: line)
  if eventType.len == 0:
    return

  if eventType.contains("tool"):
    let toolName = resolveCodexToolName(envelope)
    let toolState = resolveCodexToolState(envelope)
    let argSummary = resolveCodexToolArgSummary(envelope)
    let toolNameWithArg = if argSummary.len > 0: toolName & " " & argSummary else: toolName
    result = CodexStreamEvent(
      kind: codexEventTool,
      text: buildToolEventText(eventType, toolNameWithArg, toolState),
      rawLine: line,
    )
  elif eventType.contains("reason") or eventType.contains("think") or eventType.contains("analysis"):
    let text = resolveCodexReasoningText(envelope)
    result = CodexStreamEvent(
      kind: codexEventReasoning,
      text: if text.len > 0: text else: eventType,
      rawLine: line,
    )
  elif eventType == "message":
    result = CodexStreamEvent(
      kind: codexEventMessage,
      text: resolveCodexMessageText(envelope),
      rawLine: line,
    )
  else:
    result = CodexStreamEvent(
      kind: codexEventStatus,
      text: buildStatusEventText(eventType, resolveCodexStatusValue(envelope)),
      rawLine: line,
    )

proc buildCodexStreamEvent(line: string): CodexStreamEvent =
  ## Parse one codex JSON line and normalize it into a stream event.
  result = CodexStreamEvent(kind: codexEventStatus, text: "", rawLine: line)
  if line.len == 0:
    return

  var envelope: CodexJsonEnvelope
  let parsed = parseCodexJsonEnvelope(line, envelope)
  if parsed:
    result = buildCodexStreamEventFromEnvelope(line, envelope)

proc emitCodexEvent(onEvent: CodexEventHandler, event: CodexStreamEvent) =
  ## Emit one codex stream event when callbacks are configured.
  if onEvent.isNil:
    return
  if event.kind == codexEventStatus and event.text.len == 0:
    return
  if event.kind == codexEventMessage and event.text.len == 0:
    return
  onEvent(event)

proc emitCodexEventsFromChunk(
  onEvent: CodexEventHandler,
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
        emitCodexEvent(onEvent, buildCodexStreamEvent(line))
      lineStart = index + 1

  if lineStart < combined.len:
    pendingLine = combined[lineStart..^1]
  else:
    pendingLine = ""

proc flushPendingCodexEvents(onEvent: CodexEventHandler, pendingLine: var string) =
  ## Emit one final event for buffered partial output when present.
  let line = pendingLine.strip()
  if line.len > 0:
    emitCodexEvent(onEvent, buildCodexStreamEvent(line))
  pendingLine = ""

proc runCodexAttempt(request: CodexRunRequest, prompt: string, attemptValue: int): CodexRunResult =
  ## Run one codex attempt and capture streamed output, logs, and timeout state.
  if request.workingDir.len == 0:
    raise newException(ValueError, "workingDir is required")
  if request.model.len == 0:
    raise newException(ValueError, "model is required")

  let ticketValue = if request.ticketId.len > 0: request.ticketId else: DefaultTicketId
  let logRoot = if request.logRoot.len > 0: request.logRoot else: request.workingDir / DefaultLogRoot
  let codexBinary = if request.codexBinary.len > 0: request.codexBinary else: DefaultCodexBinary
  let noOutputTimeoutMs = resolveNoOutputTimeoutMs(request)
  let hardTimeoutMs = resolveHardTimeoutMs(request)
  let heartbeatIntervalMs = resolveHeartbeatIntervalMs(request)

  let ticketDir = logRoot / sanitizePathSegment(ticketValue)
  createDir(ticketDir)

  let attemptPrefix = &"attempt-{attemptValue:02d}"
  let logFilePath = ticketDir / (attemptPrefix & ".jsonl")
  let lastMessagePath = ticketDir / (attemptPrefix & ".last_message.txt")
  let args = buildCodexExecArgs(
    CodexRunRequest(
      workingDir: request.workingDir,
      model: request.model,
      reasoningEffort: request.reasoningEffort,
      mcpEndpoint: request.mcpEndpoint,
      skipGitRepoCheck: request.skipGitRepoCheck,
    ),
    lastMessagePath,
  )

  result.command = @[codexBinary] & args
  result.attempt = attemptValue
  result.attemptCount = 1
  result.timeoutKind = codexTimeoutNone
  result.logFile = logFilePath
  result.lastMessageFile = lastMessagePath
  result.stdout = ""
  result.lastMessage = ""

  let fullCmd = result.command.join(" ")
  logDebug("codex command: " & fullCmd)

  let logFile = open(logFilePath, fmWrite)
  defer:
    logFile.close()

  let process = startProcess(
    codexBinary,
    workingDir = request.workingDir,
    args = args,
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
  var wrappedOnEvent: CodexEventHandler = nil
  if not request.onEvent.isNil:
    wrappedOnEvent = proc(event: CodexStreamEvent) =
      if event.kind == codexEventTool:
        lastToolTime = getMonoTime()
      request.onEvent(event)

  while not stopRequested:
    if heartbeatIntervalMs > 0 and not wrappedOnEvent.isNil:
      let now = getMonoTime()
      if elapsedMs(lastOutputTime) >= heartbeatIntervalMs.int64 and elapsedMs(lastHeartbeatTime) >= heartbeatIntervalMs.int64:
        emitCodexEvent(
          wrappedOnEvent,
          CodexStreamEvent(
            kind: codexEventHeartbeat,
            text: "still working",
            rawLine: "",
          ),
        )
        lastHeartbeatTime = now

    if hardTimeoutMs > 0 and elapsedMs(startTime) >= hardTimeoutMs.int64:
      result.timeoutKind = codexTimeoutHard
      process.kill()
      stopRequested = true
    if noOutputTimeoutMs > 0 and elapsedMs(lastOutputTime) >= noOutputTimeoutMs.int64:
      result.timeoutKind = codexTimeoutNoOutput
      process.kill()
      stopRequested = true
    if progressTimeoutMs > 0 and elapsedMs(lastToolTime) >= progressTimeoutMs.int64:
      # Only fire if there has been output since the last tool call (agent is alive but not progressing).
      if elapsedMs(lastOutputTime) < elapsedMs(lastToolTime):
        result.timeoutKind = codexTimeoutProgress
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
        emitCodexEventsFromChunk(wrappedOnEvent, pendingLine, chunk)
    elif streamClosed and process.peekExitCode() != -1:
      break

    if process.peekExitCode() != -1 and not streamClosed:
      if not waitForReadable(outputFd, 0):
        streamClosed = true

  result.exitCode = process.waitForExit()
  flushPendingCodexEvents(wrappedOnEvent, pendingLine)
  if fileExists(lastMessagePath):
    result.lastMessage = readFile(lastMessagePath)

proc runCodex*(request: CodexRunRequest): CodexRunResult =
  ## Run codex with optional bounded retries and continuation prompts.
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
    result = runCodexAttempt(request, prompt, attemptValue)
    inc attemptsUsed
    result.attemptCount = attemptsUsed

    let completed = result.exitCode == 0 and result.timeoutKind == codexTimeoutNone
    if completed:
      break

    if attemptsUsed < maxAttempts:
      prompt = buildContinuationPrompt(originalPrompt, result, request.continuationPrompt, request.continuationPromptBuilder, request.workingDir)
