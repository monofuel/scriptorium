import
  std/strformat,
  ./[common, config, harness_claude_code, harness_codex, harness_typoi]

type
  AgentStreamEventKind* = enum
    agentEventHeartbeat = "heartbeat"
    agentEventReasoning = "reasoning"
    agentEventTool = "tool"
    agentEventStatus = "status"
    agentEventMessage = "message"

  AgentStreamEvent* = object
    kind*: AgentStreamEventKind
    text*: string
    rawLine*: string

  AgentEventHandler* = proc(event: AgentStreamEvent)

  AgentRunRequest* = object
    prompt*: string
    workingDir*: string
    harness*: Harness
    model*: string
    reasoningEffort*: string
    mcpEndpoint*: string
    ticketId*: string
    attempt*: int
    binary*: string
    skipGitRepoCheck*: bool
    logRoot*: string
    noOutputTimeoutMs*: int
    hardTimeoutMs*: int
    progressTimeoutMs*: int
    heartbeatIntervalMs*: int
    maxAttempts*: int
    continuationPrompt*: string
    continuationPromptBuilder*: ContinuationPromptBuilder
    onEvent*: AgentEventHandler

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
    ticketId*: string
    submitted*: bool

  AgentRunner* = proc(request: AgentRunRequest): AgentRunResult

proc mapCodexEvent(event: CodexStreamEvent): AgentStreamEvent =
  ## Convert one codex stream event into an agent stream event.
  result = AgentStreamEvent(
    text: event.text,
    rawLine: event.rawLine,
  )
  case event.kind
  of codexEventHeartbeat:
    result.kind = agentEventHeartbeat
  of codexEventReasoning:
    result.kind = agentEventReasoning
  of codexEventTool:
    result.kind = agentEventTool
  of codexEventStatus:
    result.kind = agentEventStatus
  of codexEventMessage:
    result.kind = agentEventMessage

proc mapClaudeCodeEvent(event: ClaudeCodeStreamEvent): AgentStreamEvent =
  ## Convert one Claude Code stream event into an agent stream event.
  result = AgentStreamEvent(
    text: event.text,
    rawLine: event.rawLine,
  )
  case event.kind
  of claudeCodeEventHeartbeat:
    result.kind = agentEventHeartbeat
  of claudeCodeEventReasoning:
    result.kind = agentEventReasoning
  of claudeCodeEventTool:
    result.kind = agentEventTool
  of claudeCodeEventStatus:
    result.kind = agentEventStatus
  of claudeCodeEventMessage:
    result.kind = agentEventMessage

proc mapTypoiEvent(event: TypoiStreamEvent): AgentStreamEvent =
  ## Convert one typoi stream event into an agent stream event.
  result = AgentStreamEvent(
    text: event.text,
    rawLine: event.rawLine,
  )
  case event.kind
  of typoiEventHeartbeat:
    result.kind = agentEventHeartbeat
  of typoiEventReasoning:
    result.kind = agentEventReasoning
  of typoiEventTool:
    result.kind = agentEventTool
  of typoiEventStatus:
    result.kind = agentEventStatus
  of typoiEventMessage:
    result.kind = agentEventMessage

proc runAgent*(request: AgentRunRequest): AgentRunResult =
  ## Run the configured agent backend for one coding request.
  if request.workingDir.len == 0:
    raise newException(ValueError, "workingDir is required")
  if request.model.len == 0:
    raise newException(ValueError, "model is required")

  case request.harness
  of harnessCodex:
    let codexResult = runCodex(CodexRunRequest(
      prompt: request.prompt,
      workingDir: request.workingDir,
      model: request.model,
      reasoningEffort: request.reasoningEffort,
      mcpEndpoint: request.mcpEndpoint,
      ticketId: request.ticketId,
      attempt: request.attempt,
      codexBinary: request.binary,
      skipGitRepoCheck: request.skipGitRepoCheck,
      logRoot: request.logRoot,
      noOutputTimeoutMs: request.noOutputTimeoutMs,
      hardTimeoutMs: request.hardTimeoutMs,
      progressTimeoutMs: request.progressTimeoutMs,
      heartbeatIntervalMs: request.heartbeatIntervalMs,
      maxAttempts: request.maxAttempts,
      continuationPrompt: request.continuationPrompt,
      continuationPromptBuilder: request.continuationPromptBuilder,
      onEvent: proc(event: CodexStreamEvent) =
        ## Forward codex streaming events to the optional agent callback.
        if not request.onEvent.isNil:
          request.onEvent(mapCodexEvent(event))
    ))
    result = AgentRunResult(
      backend: request.harness,
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
  of harnessClaudeCode:
    let claudeResult = runClaudeCode(ClaudeCodeRunRequest(
      prompt: request.prompt,
      workingDir: request.workingDir,
      model: request.model,
      reasoningEffort: request.reasoningEffort,
      mcpEndpoint: request.mcpEndpoint,
      ticketId: request.ticketId,
      attempt: request.attempt,
      claudeCodeBinary: request.binary,
      logRoot: request.logRoot,
      noOutputTimeoutMs: request.noOutputTimeoutMs,
      hardTimeoutMs: request.hardTimeoutMs,
      progressTimeoutMs: request.progressTimeoutMs,
      heartbeatIntervalMs: request.heartbeatIntervalMs,
      maxAttempts: request.maxAttempts,
      continuationPrompt: request.continuationPrompt,
      continuationPromptBuilder: request.continuationPromptBuilder,
      onEvent: proc(event: ClaudeCodeStreamEvent) =
        ## Forward Claude Code streaming events to the optional agent callback.
        if not request.onEvent.isNil:
          request.onEvent(mapClaudeCodeEvent(event))
    ))
    result = AgentRunResult(
      backend: request.harness,
      command: claudeResult.command,
      exitCode: claudeResult.exitCode,
      attempt: claudeResult.attempt,
      attemptCount: claudeResult.attemptCount,
      stdout: claudeResult.stdout,
      logFile: claudeResult.logFile,
      lastMessageFile: claudeResult.lastMessageFile,
      lastMessage: claudeResult.lastMessage,
      timeoutKind: $claudeResult.timeoutKind,
    )
  of harnessTypoi:
    let typoiResult = runTypoi(TypoiRunRequest(
      prompt: request.prompt,
      workingDir: request.workingDir,
      model: request.model,
      reasoningEffort: request.reasoningEffort,
      mcpEndpoint: request.mcpEndpoint,
      ticketId: request.ticketId,
      attempt: request.attempt,
      typoiBinary: request.binary,
      logRoot: request.logRoot,
      noOutputTimeoutMs: request.noOutputTimeoutMs,
      hardTimeoutMs: request.hardTimeoutMs,
      progressTimeoutMs: request.progressTimeoutMs,
      heartbeatIntervalMs: request.heartbeatIntervalMs,
      maxAttempts: request.maxAttempts,
      continuationPrompt: request.continuationPrompt,
      continuationPromptBuilder: request.continuationPromptBuilder,
      onEvent: proc(event: TypoiStreamEvent) =
        ## Forward typoi streaming events to the optional agent callback.
        if not request.onEvent.isNil:
          request.onEvent(mapTypoiEvent(event))
    ))
    result = AgentRunResult(
      backend: request.harness,
      command: typoiResult.command,
      exitCode: typoiResult.exitCode,
      attempt: typoiResult.attempt,
      attemptCount: typoiResult.attemptCount,
      stdout: typoiResult.stdout,
      logFile: typoiResult.logFile,
      lastMessageFile: typoiResult.lastMessageFile,
      lastMessage: typoiResult.lastMessage,
      timeoutKind: $typoiResult.timeoutKind,
    )
