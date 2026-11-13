import
  std/[json, tables],
  acport,
  ./[common, config]

type
  AgentStreamEventKind* = enum
    agentEventHeartbeat = "heartbeat"
    agentEventReasoning = "reasoning"
    agentEventTool = "tool"
    agentEventStatus = "status"
    agentEventMessage = "message"
    agentEventPlan = "plan"
    agentEventUnknown = "unknown"

  AgentAccessPolicy* = enum
    accessFull, accessReadOnly, accessRestricted

  AgentFailureKind* = enum
    failureNone, failureCancelled, failureTimeout, failureTransport,
    failureProtocol, failureRpc, failureRefused, failureLimit

  AgentStreamEvent* = object
    kind*: AgentStreamEventKind
    text*: string
    rawLine*: string
    update*: SessionUpdate

  AgentEventHandler* = proc(event: AgentStreamEvent)

  AgentRunRequest* = object
    prompt*: string
    workingDir*: string
    homeDirectory*: string
    harness*: Harness
    acpAgent*: string
    profile*: AcpAgentProfile
    configOptions*: Table[string, JsonNode]
    accessPolicy*: AgentAccessPolicy
    allowedWritePaths*: seq[string]
    resumeSessionId*: string
    conversationKey*: string
    sessionRoot*: string
    restoreSession*: bool
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
    onProcessStarted*: ProcessStartedHandler
    cancellationRequested*: CancellationCheck
    allowedTools*: seq[string]

  AgentRunResult* = object
    backend*: Harness
    acpAgent*: string
    sessionId*: string
    model*: string
    outputBytes*: int
    stopReason*: StopReason
    failureKind*: AgentFailureKind
    errorCode*: int
    errorMessage*: string
    errorData*: JsonNode
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
    cancelled*: bool

  AgentRunner* = proc(request: AgentRunRequest): AgentRunResult

