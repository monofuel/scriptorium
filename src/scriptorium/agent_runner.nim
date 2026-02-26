import
  std/strformat,
  ./[config, harness_codex]

type
  AgentRunRequest* = object
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

  AgentRunResult* = object
    backend*: Harness
    command*: seq[string]
    exitCode*: int
    attempt*: int
    attemptCount*: int
    stdout*: string
    logFile*: string
    lastMessageFile*: string
    lastMessage*: string
    timeoutKind*: string

  AgentRunner* = proc(request: AgentRunRequest): AgentRunResult

proc runAgent*(request: AgentRunRequest): AgentRunResult =
  ## Run the configured agent backend for one coding request.
  if request.workingDir.len == 0:
    raise newException(ValueError, "workingDir is required")
  if request.model.len == 0:
    raise newException(ValueError, "model is required")

  let backend = harness(request.model)
  case backend
  of harnessCodex:
    let codexResult = runCodex(CodexRunRequest(
      prompt: request.prompt,
      workingDir: request.workingDir,
      model: request.model,
      ticketId: request.ticketId,
      attempt: request.attempt,
      codexBinary: request.codexBinary,
      skipGitRepoCheck: request.skipGitRepoCheck,
      logRoot: request.logRoot,
      noOutputTimeoutMs: request.noOutputTimeoutMs,
      hardTimeoutMs: request.hardTimeoutMs,
      maxAttempts: request.maxAttempts,
      continuationPrompt: request.continuationPrompt,
    ))
    result = AgentRunResult(
      backend: backend,
      command: codexResult.command,
      exitCode: codexResult.exitCode,
      attempt: codexResult.attempt,
      attemptCount: codexResult.attemptCount,
      stdout: codexResult.stdout,
      logFile: codexResult.logFile,
      lastMessageFile: codexResult.lastMessageFile,
      lastMessage: codexResult.lastMessage,
      timeoutKind: $codexResult.timeoutKind,
    )
  else:
    raise newException(ValueError, fmt"agent backend '{backend}' is not implemented")
