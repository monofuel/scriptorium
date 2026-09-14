import
  std/[json, monotimes, os, osproc, sequtils, posix, streams, strformat, strutils, times],
  ./[agent_runner_types, config, process_lock]

proc runHermes*(request: AgentRunRequest): AgentRunResult =
  ## Consume the structured protocol from the container runner.
  let
    binary = if request.binary.len > 0: request.binary else: "coworld-hermes-runner"
    campaign = request.ticketId
  if campaign.len == 0 or campaign.anyIt(it notin {'a'..'z', '0'..'9', '-', '_'}):
    raise newException(ValueError, "Hermes requires a safe campaign identifier")
  let
    logDir = request.logRoot / campaign
    attempt = max(1, request.attempt)
    prefix = &"attempt-{attempt:02d}"
  createDir(logDir)
  result = AgentRunResult(backend: harnessHermes, command: @[binary],
    attempt: attempt, attemptCount: 1, timeoutKind: "none",
    logFile: logDir / (prefix & ".jsonl"),
    lastMessageFile: logDir / (prefix & ".last_message.txt"))
  let
    log = open(result.logFile, fmWrite)
    process = startProcessGuarded(binary, workingDir = request.workingDir,
      options = {poUsePath, poStdErrToStdOut})
  defer: log.close()
  defer:
    if process.running():
      process.terminate()
      if process.waitForExit(20_000) == -1:
        process.kill()
        discard process.waitForExit()
    process.close()
  if not request.onProcessStarted.isNil:
    request.onProcessStarted(process.processID())
  process.inputStream.write($( %*{
    "prompt": request.prompt, "workingDir": request.workingDir,
    "campaign": campaign, "attempt": attempt, "model": request.model,
    "hardTimeoutMs": request.hardTimeoutMs,
    "progressTimeoutMs": request.progressTimeoutMs,
    "noOutputTimeoutMs": request.noOutputTimeoutMs
  }))
  process.inputStream.close()
  var
    pending = ""
    cancelled = false
    finished = false
    failed = false
    cancelStarted = getMonoTime()
  let fd = cint(process.outputHandle)
  while true:
    if not cancelled and not request.cancellationRequested.isNil and request.cancellationRequested():
      cancelled = true
      cancelStarted = getMonoTime()
      process.terminate()
    if cancelled and (getMonoTime() - cancelStarted).inSeconds >= 20:
      process.kill()
      break
    var
      descriptors: TFdSet
      timeout = Timeval(tv_sec: posix.Time(0), tv_usec: Suseconds(100_000))
    FD_ZERO(descriptors)
    FD_SET(fd, descriptors)
    let ready = select(fd + 1, addr descriptors, nil, nil, addr timeout)
    if ready < 0:
      if osLastError() == OSErrorCode(EINTR): continue
      raiseOSError(osLastError())
    if ready == 0:
      if not process.running(): break
      continue
    var buffer = newString(4096)
    let count = posix.read(fd, addr buffer[0], buffer.len)
    if count < 0:
      if osLastError() == OSErrorCode(EINTR): continue
      raiseOSError(osLastError())
    if count == 0: break
    buffer.setLen(count)
    pending.add(buffer)
    while '\n' in pending:
      let endIndex = pending.find('\n')
      let line = pending[0..<endIndex]
      pending = pending[endIndex + 1..^1]
      if line.len == 0: continue
      log.writeLine(line)
      log.flushFile()
      let node = parseJson(line)
      let kind = node{"kind"}.getStr()
      let message = node{"text"}.getStr()
      if kind == "result":
        failed = node{"failed"}.getBool()
        result.lastMessage = message
        result.timeoutKind = node{"timeoutKind"}.getStr("none")
        result.cancelled = node{"cancelled"}.getBool() or cancelled
        finished = true
      else:
        let eventKind = case kind
          of "tool": agentEventTool
          of "message": agentEventMessage
          of "heartbeat": agentEventHeartbeat
          else: agentEventStatus
        if not request.onEvent.isNil:
          request.onEvent(AgentStreamEvent(kind: eventKind, text: message, rawLine: line))
  result.exitCode = process.waitForExit()
  if failed and result.exitCode == 0:
    result.exitCode = 1
  result.cancelled = result.cancelled or cancelled
  if not finished and not result.cancelled:
    result.exitCode = 1
    result.lastMessage = "Hermes runner exited without its result record"
  writeFile(result.lastMessageFile, result.lastMessage)
