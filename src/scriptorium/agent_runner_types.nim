import ./[common, config]

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
    homeDirectory*: string
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
    onProcessStarted*: ProcessStartedHandler
    cancellationRequested*: CancellationCheck
    allowedTools*: seq[string]

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
    cancelled*: bool

  AgentRunner* = proc(request: AgentRunRequest): AgentRunResult

