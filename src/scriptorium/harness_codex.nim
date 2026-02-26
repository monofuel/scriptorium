import
  std/[monotimes, os, osproc, posix, streams, strformat, strutils, times]

const
  DefaultCodexBinary = "codex"
  DefaultCodexDeveloperInstructions = "developer_instructions=\"\""
  DefaultCodexMcpServers = "mcp_servers={}"
  DefaultTicketId = "adhoc"
  DefaultAttempt = 1
  DefaultLogRoot = ".scriptorium/logs"
  DefaultPollIntervalMs = 100
  DefaultMaxAttempts = 1
  DefaultNoOutputTimeoutMs = 0
  DefaultHardTimeoutMs = 0
  OutputChunkSize = 4096
  ContinuationTailChars = 1200

type
  CodexTimeoutKind* = enum
    codexTimeoutNone = "none"
    codexTimeoutNoOutput = "no-output"
    codexTimeoutHard = "hard"

  CodexRunRequest* = object
    prompt*: string
    workingDir*: string
    model*: string
    ticketId*: string
    attempt*: int
    codexBinary*: string
    skipGitRepoCheck*: bool
    logRoot*: string
    noOutputTimeoutMs*: int
    hardTimeoutMs*: int
    maxAttempts*: int
    continuationPrompt*: string

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
      raise newException(IOError, fmt"select failed for codex output fd {fd}")
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
      raise newException(IOError, fmt"read failed for codex output fd {fd}")
    if bytesRead == 0:
      result = ("", true)
    else:
      buffer.setLen(bytesRead)
      result = (buffer, false)
    break

proc buildCodexExecArgs*(request: CodexRunRequest, lastMessagePath: string): seq[string] =
  ## Build the codex exec argument list in a deterministic order.
  if request.workingDir.len == 0:
    raise newException(ValueError, "workingDir is required")
  if request.model.len == 0:
    raise newException(ValueError, "model is required")
  if lastMessagePath.len == 0:
    raise newException(ValueError, "lastMessagePath is required")

  result = @[
    "-c",
    DefaultCodexDeveloperInstructions,
    "-c",
    DefaultCodexMcpServers,
    "exec",
    "--json",
    "--output-last-message",
    lastMessagePath,
    "--cd",
    request.workingDir,
    "--model",
    request.model,
    "--dangerously-bypass-approvals-and-sandbox",
  ]

  if request.skipGitRepoCheck:
    result.add("--skip-git-repo-check")

  result.add("-")

proc buildContinuationPrompt(
  originalPrompt: string,
  previousResult: CodexRunResult,
  customContinuationPrompt: string,
): string =
  ## Build the prompt text for a retry attempt after a failed run.
  let summarySource = if previousResult.lastMessage.len > 0: previousResult.lastMessage else: previousResult.stdout
  let summaryTail = truncateTail(summarySource, ContinuationTailChars).strip()
  let continuationText = if customContinuationPrompt.len > 0:
      customContinuationPrompt.strip()
    else:
      "Continue from the previous attempt and complete the ticket."

  result = originalPrompt.strip() & "\n\n" &
    fmt"Attempt {previousResult.attempt} failed with exit code {previousResult.exitCode} (timeout: {previousResult.timeoutKind}).\n" &
    "Last output excerpt:\n" &
    summaryTail & "\n\n" &
    continuationText & "\n"

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

  let ticketDir = logRoot / sanitizePathSegment(ticketValue)
  createDir(ticketDir)

  let attemptPrefix = fmt"attempt-{attemptValue:02d}"
  let logFilePath = ticketDir / (attemptPrefix & ".jsonl")
  let lastMessagePath = ticketDir / (attemptPrefix & ".last_message.txt")
  let args = buildCodexExecArgs(
    CodexRunRequest(
      workingDir: request.workingDir,
      model: request.model,
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
  var streamClosed = false
  var stopRequested = false

  while not stopRequested:
    if hardTimeoutMs > 0 and elapsedMs(startTime) >= hardTimeoutMs.int64:
      result.timeoutKind = codexTimeoutHard
      process.kill()
      stopRequested = true
    if noOutputTimeoutMs > 0 and elapsedMs(lastOutputTime) >= noOutputTimeoutMs.int64:
      result.timeoutKind = codexTimeoutNoOutput
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
    elif streamClosed and process.peekExitCode() != -1:
      break

    if process.peekExitCode() != -1 and not streamClosed:
      if not waitForReadable(outputFd, 0):
        streamClosed = true

  result.exitCode = process.waitForExit()
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
      prompt = buildContinuationPrompt(originalPrompt, result, request.continuationPrompt)
