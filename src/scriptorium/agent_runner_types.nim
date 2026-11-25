import
  std/[json, locks, options, tables],
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

  InteractionBridge* = object
    ## Shared rendezvous through which an embedding ACP server answers a native
    ## agent's permission and question requests on its own request thread.
    lock*: Lock
    requests*: Channel[string]
    replies*: Channel[string]
    completions*: Channel[string]
      ## URL elicitation completions reported by native agents, in arrival order.
    activeId*: int
      ## Identifier of the request currently awaiting an answer, or zero.
    nextId*: int

  AgentRunRequest* = object
    activityRole*: string
    activityTask*: string
    activityAreaId*: string
    activityWorkPath*: string
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
    attachments*: seq[ContentBlock]
      ## Structured prompt content sent after the built text prompt.
    extraMcpServers*: seq[JsonNode]
      ## Caller-supplied ACP MCP servers; never persisted in session records.
    systemPrompt*: Option[SystemPrompt]
    interaction*: ptr InteractionBridge
    elicitationModes*: set[ElicitationMode]
      ## Question modes the embedding client advertised; only these reach the native agent.

  AgentRunResult* = object
    backend*: Harness
    acpAgent*: string
    sessionId*: string
    model*: string
    outputBytes*: int
    stopReason*: StopReason
    stopReasonReceived*: bool
    failureKind*: AgentFailureKind
    errorCode*: int
    errorMessage*: string
    errorData*: JsonNode
    command*: seq[string]
    exitCode*: int
    attempt*: int
    attemptCount*: int
    stdout*: string
      ## Deprecated fixture compatibility; ACP execution leaves this empty.
    logFile*: string
    lastMessageFile*: string
    lastMessage*: string
    transcriptText*: string
      ## All assistant chunks, including commentary before tool activity.
    failedTools*: seq[string]
    deniedPermissions*: int
    cancellationSource*: string
    timeoutKind*: string
    ticketId*: string
    submitted*: bool
    cancelled*: bool

  AgentRunner* = proc(request: AgentRunRequest): AgentRunResult


var
  agentActivityStarted*: proc(request: AgentRunRequest): string
  agentActivityEvent*: proc(id: string, event: AgentStreamEvent)
  agentActivityFinished*: proc(id: string, response: AgentRunResult, raised: bool)
