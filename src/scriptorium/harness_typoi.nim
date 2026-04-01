import
  std/[monotimes, os, osproc, posix, streams, strformat, strutils, times],
  jsony,
  ./[common, logging, prompt_catalog]

const
  DefaultTypoiBinary = "typoi"
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

type
  TypoiStreamEventKind* = enum
    typoiEventHeartbeat = "heartbeat"
    typoiEventReasoning = "reasoning"
    typoiEventTool = "tool"
    typoiEventStatus = "status"
    typoiEventMessage = "message"

  TypoiStreamEvent* = object
    kind*: TypoiStreamEventKind
    text*: string
    rawLine*: string

  TypoiEventHandler* = proc(event: TypoiStreamEvent)

  TypoiTimeoutKind* = enum
    typoiTimeoutNone = "none"
    typoiTimeoutNoOutput = "no-output"
    typoiTimeoutHard = "hard"
    typoiTimeoutProgress = "progress"

  TypoiRunRequest* = object
    prompt*: string
    workingDir*: string
    model*: string
    reasoningEffort*: string
    mcpEndpoint*: string
    ticketId*: string
    attempt*: int
    typoiBinary*: string
    logRoot*: string
    noOutputTimeoutMs*: int
    hardTimeoutMs*: int
    progressTimeoutMs*: int
    heartbeatIntervalMs*: int
    onEvent*: TypoiEventHandler
    maxAttempts*: int
    continuationPrompt*: string
    continuationPromptBuilder*: ContinuationPromptBuilder

  TypoiRunResult* = object
    command*: seq[string]
    exitCode*: int
    attempt*: int
    attemptCount*: int
    stdout*: string
    logFile*: string
    lastMessageFile*: string
    lastMessage*: string
    timeoutKind*: TypoiTimeoutKind

  TypoiJsonEnvelope = object
    `type`: string
    text: string
    name: string

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

proc resolveAttemptBase(request: TypoiRunRequest): int =
  ## Resolve the base attempt number for the current run.
  if request.attempt > 0:
    result = request.attempt
  else:
    result = DefaultAttempt

proc resolveMaxAttempts(request: TypoiRunRequest): int =
  ## Resolve how many typoi attempts are allowed for the current run.
  if request.maxAttempts > 0:
    result = request.maxAttempts
  else:
    result = DefaultMaxAttempts

proc resolveNoOutputTimeoutMs(request: TypoiRunRequest): int =
  ## Resolve the no-output watchdog timeout in milliseconds.
  if request.noOutputTimeoutMs > 0:
    result = request.noOutputTimeoutMs
  else:
    result = DefaultNoOutputTimeoutMs

proc resolveHardTimeoutMs(request: TypoiRunRequest): int =
  ## Resolve the hard watchdog timeout in milliseconds.
  if request.hardTimeoutMs > 0:
    result = request.hardTimeoutMs
  else:
    result = DefaultHardTimeoutMs

proc resolveHeartbeatIntervalMs(request: TypoiRunRequest): int =
  ## Resolve how often heartbeat events should be emitted in milliseconds.
  if request.heartbeatIntervalMs > 0:
    result = request.heartbeatIntervalMs
  else:
    result = DefaultHeartbeatIntervalMs

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
      raise newException(IOError, &"select failed for typoi output fd {fd}")
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
      raise newException(IOError, &"read failed for typoi output fd {fd}")
    if bytesRead == 0:
      result = ("", true)
    else:
      buffer.setLen(bytesRead)
      result = (buffer, false)
    break

proc buildTypoiExecArgs*(request: TypoiRunRequest, lastMessagePath: string): seq[string] =
  ## Build the typoi exec argument list in a deterministic order.
  if lastMessagePath.len == 0:
    raise newException(ValueError, "lastMessagePath is required")

  result = @[
    "--json-stream",
    "--yolo",
    "--output-last-message",
    lastMessagePath,
  ]

  let cleanEndpoint = request.mcpEndpoint.strip()
  if cleanEndpoint.len > 0:
    var endpointBase = cleanEndpoint
    while endpointBase.endsWith("/"):
      endpointBase.setLen(endpointBase.len - 1)
    if endpointBase.len > 0:
      result.add("--mcp-server-url")
      result.add(endpointBase & "/mcp")

  if request.model.len > 0:
    result.add("--model")
    result.add(request.model)
    if request.model.startsWith("claude-"):
      result.add("--provider")
      result.add("anthropic")

  let cleanEffort = request.reasoningEffort.strip()
  if cleanEffort.len > 0:
    result.add("--reasoning-effort")
    result.add(cleanEffort)

proc buildTypoiStreamEvent(line: string): TypoiStreamEvent =
  ## Parse one typoi JSONL line and normalize it into a stream event.
  result = TypoiStreamEvent(kind: typoiEventStatus, text: "", rawLine: line)
  if line.len == 0:
    return

  var envelope: TypoiJsonEnvelope
  try:
    envelope = fromJson(line, TypoiJsonEnvelope)
  except ValueError:
    return

  let eventType = envelope.`type`.strip().toLowerAscii()
  if eventType.len == 0:
    return

  case eventType
  of "tool":
    let toolName = envelope.name.strip()
    let toolText = envelope.text.strip()
    let text = if toolName.len > 0 and toolText.len > 0:
        toolName & ": " & toolText
      elif toolName.len > 0:
        toolName
      else:
        toolText
    result = TypoiStreamEvent(
      kind: typoiEventTool,
      text: text,
      rawLine: line,
    )
  of "message":
    result = TypoiStreamEvent(
      kind: typoiEventMessage,
      text: envelope.text.strip(),
      rawLine: line,
    )
  of "status":
    result = TypoiStreamEvent(
      kind: typoiEventStatus,
      text: envelope.text.strip(),
      rawLine: line,
    )
  else:
    result = TypoiStreamEvent(
      kind: typoiEventStatus,
      text: eventType,
      rawLine: line,
    )

proc emitTypoiEvent(onEvent: TypoiEventHandler, event: TypoiStreamEvent) =
  ## Emit one typoi stream event when callbacks are configured.
  if onEvent.isNil:
    return
  if event.kind == typoiEventStatus and event.text.len == 0:
    return
  if event.kind == typoiEventMessage and event.text.len == 0:
    return
  onEvent(event)

proc emitTypoiEventsFromChunk(
  onEvent: TypoiEventHandler,
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
        emitTypoiEvent(onEvent, buildTypoiStreamEvent(line))
      lineStart = index + 1

  if lineStart < combined.len:
    pendingLine = combined[lineStart..^1]
  else:
    pendingLine = ""

proc flushPendingTypoiEvents(onEvent: TypoiEventHandler, pendingLine: var string) =
  ## Emit one final event for buffered partial output when present.
  let line = pendingLine.strip()
  if line.len > 0:
    emitTypoiEvent(onEvent, buildTypoiStreamEvent(line))
  pendingLine = ""

proc buildContinuationPrompt(
  originalPrompt: string,
  previousResult: TypoiRunResult,
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

proc runTypoiAttempt(request: TypoiRunRequest, prompt: string, attemptValue: int): TypoiRunResult =
  ## Run one typoi attempt and capture streamed output, logs, and timeout state.
  let ticketValue = if request.ticketId.len > 0: request.ticketId else: DefaultTicketId
  let logRoot = if request.logRoot.len > 0: request.logRoot else: request.workingDir / DefaultLogRoot
  let typoiBinary = if request.typoiBinary.len > 0: request.typoiBinary else: DefaultTypoiBinary
  let noOutputTimeoutMs = resolveNoOutputTimeoutMs(request)
  let hardTimeoutMs = resolveHardTimeoutMs(request)
  let heartbeatIntervalMs = resolveHeartbeatIntervalMs(request)

  let ticketDir = logRoot / sanitizePathSegment(ticketValue)
  createDir(ticketDir)

  let attemptPrefix = &"attempt-{attemptValue:02d}"
  let logFilePath = ticketDir / (attemptPrefix & ".jsonl")
  let lastMessagePath = ticketDir / (attemptPrefix & ".last_message.txt")
  let args = buildTypoiExecArgs(
    TypoiRunRequest(
      model: request.model,
      reasoningEffort: request.reasoningEffort,
      mcpEndpoint: request.mcpEndpoint,
    ),
    lastMessagePath,
  )

  result.command = @[typoiBinary] & args
  result.attempt = attemptValue
  result.attemptCount = 1
  result.timeoutKind = typoiTimeoutNone
  result.logFile = logFilePath
  result.lastMessageFile = lastMessagePath
  result.stdout = ""
  result.lastMessage = ""

  let fullCmd = result.command.join(" ")
  logDebug("typoi command: " & fullCmd)

  let logFile = open(logFilePath, fmWrite)
  defer:
    logFile.close()

  let process = startProcess(
    typoiBinary,
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
  var wrappedOnEvent: TypoiEventHandler = nil
  if not request.onEvent.isNil:
    wrappedOnEvent = proc(event: TypoiStreamEvent) =
      if event.kind == typoiEventTool:
        lastToolTime = getMonoTime()
      request.onEvent(event)

  while not stopRequested:
    if heartbeatIntervalMs > 0 and not wrappedOnEvent.isNil:
      let now = getMonoTime()
      if elapsedMs(lastOutputTime) >= heartbeatIntervalMs.int64 and elapsedMs(lastHeartbeatTime) >= heartbeatIntervalMs.int64:
        emitTypoiEvent(
          wrappedOnEvent,
          TypoiStreamEvent(
            kind: typoiEventHeartbeat,
            text: "still working",
            rawLine: "",
          ),
        )
        lastHeartbeatTime = now

    if hardTimeoutMs > 0 and elapsedMs(startTime) >= hardTimeoutMs.int64:
      result.timeoutKind = typoiTimeoutHard
      process.kill()
      stopRequested = true
    if noOutputTimeoutMs > 0 and elapsedMs(lastOutputTime) >= noOutputTimeoutMs.int64:
      result.timeoutKind = typoiTimeoutNoOutput
      process.kill()
      stopRequested = true
    if progressTimeoutMs > 0 and elapsedMs(lastToolTime) >= progressTimeoutMs.int64:
      if elapsedMs(lastOutputTime) < elapsedMs(lastToolTime):
        result.timeoutKind = typoiTimeoutProgress
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
        emitTypoiEventsFromChunk(wrappedOnEvent, pendingLine, chunk)
    elif streamClosed and process.peekExitCode() != -1:
      break

    if process.peekExitCode() != -1 and not streamClosed:
      if not waitForReadable(outputFd, 0):
        streamClosed = true

  result.exitCode = process.waitForExit()
  flushPendingTypoiEvents(wrappedOnEvent, pendingLine)
  if fileExists(lastMessagePath):
    result.lastMessage = readFile(lastMessagePath)

proc runTypoi*(request: TypoiRunRequest): TypoiRunResult =
  ## Run typoi with optional bounded retries and continuation prompts.
  if request.workingDir.len == 0:
    raise newException(ValueError, "workingDir is required")

  let baseAttempt = resolveAttemptBase(request)
  let maxAttempts = resolveMaxAttempts(request)
  let originalPrompt = request.prompt
  var prompt = originalPrompt
  var attemptsUsed = 0

  while attemptsUsed < maxAttempts:
    let attemptValue = baseAttempt + attemptsUsed
    result = runTypoiAttempt(request, prompt, attemptValue)
    inc attemptsUsed
    result.attemptCount = attemptsUsed

    let completed = result.exitCode == 0 and result.timeoutKind == typoiTimeoutNone
    if completed:
      break

    if attemptsUsed < maxAttempts:
      prompt = buildContinuationPrompt(originalPrompt, result, request.continuationPrompt, request.continuationPromptBuilder, request.workingDir)
