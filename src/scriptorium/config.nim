import
  std/[os, strutils],
  jsony

type
  Harness* = enum
    harnessClaudeCode = "claude-code"
    harnessCodex = "codex"
    harnessTypoi = "typoi"

const
  ConfigFile = "scriptorium.json"
  DefaultArchitectModel = "claude-opus-4-6"
  DefaultCodingModel = "claude-sonnet-4-6"
  DefaultManagerModel = "claude-sonnet-4-6"
  DefaultReviewerModel = "claude-sonnet-4-6"
  DefaultAuditModel* = "claude-haiku-4-5-20251001"
  DefaultHarness = harnessClaudeCode
  DefaultReasoningEffort = ""
  DefaultLocalEndpoint = "http://127.0.0.1:8097"
  DefaultDashboardPort = 8098
  DefaultDashboardHost = "127.0.0.1"
  DefaultFeedbackTimeoutMs* = 7_200_000

type
  AgentConfig* = object
    harness*: Harness
    model*: string
    reasoningEffort*: string
    hardTimeout*: int
    noOutputTimeout*: int
    progressTimeout*: int

  AgentConfigs* = object
    architect*: AgentConfig
    coding*: AgentConfig
    manager*: AgentConfig
    reviewer*: AgentConfig
    audit*: AgentConfig

  Endpoints* = object
    local*: string

  DiscordConfig* = object
    enabled*: bool
    serverId*: string
    channelId*: string
    allowedUserIds*: seq[string]
    chatHistoryCount*: int

  MattermostConfig* = object
    enabled*: bool
    url*: string
    channelId*: string
    allowedUserIds*: seq[string]
    chatHistoryCount*: int

  LoopConfig* = object
    enabled*: bool
    feedback*: string
    goal*: string
    maxIterations*: int
    feedbackTimeoutMs*: int

  DashboardConfig* = object
    host*: string
    port*: int

  RemoteSyncConfig* = object
    enabled*: bool
    primaryRemote*: string
    remotes*: seq[string]
    syncIntervalSeconds*: int

  ConcurrencyConfig* = object
    maxAgents*: int
    tokenBudgetMB*: int

  TimeoutConfig* = object
    codingAgentHardTimeoutMs*: int
    codingAgentNoOutputTimeoutMs*: int
    codingAgentProgressTimeoutMs*: int
    codingAgentMaxAttempts*: int

  Config* = object
    agents*: AgentConfigs
    endpoints*: Endpoints
    concurrency*: ConcurrencyConfig
    timeouts*: TimeoutConfig
    discord*: DiscordConfig
    mattermost*: MattermostConfig
    loop*: LoopConfig
    dashboard*: DashboardConfig
    remoteSync*: RemoteSyncConfig
    syncAgentsMd*: bool
    logLevel*: string
    fileLogLevel*: string

proc defaultAgentConfig(model: string, hardTimeout: int = 0,
    noOutputTimeout: int = 0, progressTimeout: int = 0): AgentConfig =
  ## Return an AgentConfig populated with default values for a given model and timeouts.
  AgentConfig(
    harness: DefaultHarness,
    model: model,
    reasoningEffort: DefaultReasoningEffort,
    hardTimeout: hardTimeout,
    noOutputTimeout: noOutputTimeout,
    progressTimeout: progressTimeout,
  )

proc defaultConfig*(): Config =
  ## Return a Config populated with default values.
  Config(
    agents: AgentConfigs(
      architect: defaultAgentConfig(DefaultArchitectModel,
        hardTimeout = 7_200_000, noOutputTimeout = 600_000),
      coding: defaultAgentConfig(DefaultCodingModel,
        hardTimeout = 14_400_000, noOutputTimeout = 300_000, progressTimeout = 600_000),
      manager: defaultAgentConfig(DefaultManagerModel,
        hardTimeout = 3_600_000, noOutputTimeout = 300_000),
      reviewer: defaultAgentConfig(DefaultReviewerModel,
        hardTimeout = 3_600_000, noOutputTimeout = 300_000),
      audit: defaultAgentConfig(DefaultAuditModel),
    ),
    endpoints: Endpoints(
      local: DefaultLocalEndpoint,
    ),
    concurrency: ConcurrencyConfig(
      maxAgents: 1,
      tokenBudgetMB: 0,
    ),
    timeouts: TimeoutConfig(
      codingAgentHardTimeoutMs: 14_400_000,
      codingAgentNoOutputTimeoutMs: 300_000,
      codingAgentProgressTimeoutMs: 600_000,
      codingAgentMaxAttempts: 5,
    ),
    remoteSync: RemoteSyncConfig(
      enabled: false,
      primaryRemote: "gitea",
      remotes: @[],
      syncIntervalSeconds: 60,
    ),
    discord: DiscordConfig(enabled: false, serverId: "", channelId: "", allowedUserIds: @[], chatHistoryCount: 8),
    mattermost: MattermostConfig(enabled: false, url: "", channelId: "", allowedUserIds: @[], chatHistoryCount: 8),
    loop: LoopConfig(enabled: false, feedback: "", goal: "", maxIterations: 0, feedbackTimeoutMs: DefaultFeedbackTimeoutMs),
    dashboard: DashboardConfig(host: DefaultDashboardHost, port: DefaultDashboardPort),
    syncAgentsMd: true,
  )

proc discordTokenPresent*(): bool =
  ## Return whether the DISCORD_TOKEN environment variable is set.
  getEnv("DISCORD_TOKEN").len > 0

proc mattermostTokenPresent*(): bool =
  ## Return whether the MATTERMOST_TOKEN environment variable is set.
  getEnv("MATTERMOST_TOKEN").len > 0

proc resolveModel*(model: string): string =
  ## Translate Anthropic-style model IDs to Bedrock format when
  ## CLAUDE_CODE_USE_BEDROCK is set. Non-claude models pass through unchanged.
  if getEnv("CLAUDE_CODE_USE_BEDROCK", "").len == 0:
    return model
  case model
  of "claude-opus-4-6": "us.anthropic.claude-opus-4-6-v1"
  of "claude-sonnet-4-6": "us.anthropic.claude-sonnet-4-6"
  of "claude-haiku-4-5-20251001": "us.anthropic.claude-haiku-4-5-20251001-v1:0"
  else: model

proc inferHarness*(model: string): Harness =
  ## Infer a harness from a model name prefix. Intended for test convenience only.
  if model.startsWith("claude-"):
    harnessClaudeCode
  elif model.startsWith("codex-") or model.startsWith("gpt-"):
    harnessCodex
  else:
    harnessTypoi

proc mergeAgentConfig(base: var AgentConfig, parsed: AgentConfig) =
  ## Merge non-empty parsed fields into base.
  if parsed.model.len > 0:
    base.model = parsed.model
  if parsed.reasoningEffort.len > 0:
    base.reasoningEffort = parsed.reasoningEffort
  if parsed.hardTimeout > 0:
    base.hardTimeout = parsed.hardTimeout
  if parsed.noOutputTimeout > 0:
    base.noOutputTimeout = parsed.noOutputTimeout
  if parsed.progressTimeout > 0:
    base.progressTimeout = parsed.progressTimeout
  let parsedHarnessStr = $parsed.harness
  if parsedHarnessStr.len > 0 and parsedHarnessStr != $DefaultHarness:
    base.harness = parsed.harness
  elif parsed.model.len > 0 and parsedHarnessStr == $DefaultHarness:
    base.harness = inferHarness(parsed.model)

proc loadConfig*(repoPath: string): Config =
  ## Load scriptorium.json from repoPath, falling back to defaults for missing fields.
  let path = repoPath / ConfigFile
  if not fileExists(path):
    return defaultConfig()
  let raw = readFile(path)
  result = defaultConfig()
  let parsed = fromJson(raw, Config)
  mergeAgentConfig(result.agents.architect, parsed.agents.architect)
  mergeAgentConfig(result.agents.coding, parsed.agents.coding)
  mergeAgentConfig(result.agents.manager, parsed.agents.manager)
  mergeAgentConfig(result.agents.reviewer, parsed.agents.reviewer)
  mergeAgentConfig(result.agents.audit, parsed.agents.audit)
  if parsed.endpoints.local.len > 0:
    result.endpoints.local = parsed.endpoints.local
  if parsed.concurrency.maxAgents > 0:
    result.concurrency.maxAgents = parsed.concurrency.maxAgents
  if parsed.concurrency.tokenBudgetMB > 0:
    result.concurrency.tokenBudgetMB = parsed.concurrency.tokenBudgetMB
  if parsed.timeouts.codingAgentHardTimeoutMs > 0:
    result.timeouts.codingAgentHardTimeoutMs = parsed.timeouts.codingAgentHardTimeoutMs
  if parsed.timeouts.codingAgentNoOutputTimeoutMs > 0:
    result.timeouts.codingAgentNoOutputTimeoutMs = parsed.timeouts.codingAgentNoOutputTimeoutMs
  if parsed.timeouts.codingAgentProgressTimeoutMs > 0:
    result.timeouts.codingAgentProgressTimeoutMs = parsed.timeouts.codingAgentProgressTimeoutMs
  if parsed.timeouts.codingAgentMaxAttempts > 0:
    result.timeouts.codingAgentMaxAttempts = parsed.timeouts.codingAgentMaxAttempts
  if raw.contains("\"discord\""):
    result.discord.enabled = parsed.discord.enabled
    if parsed.discord.serverId.len > 0:
      result.discord.serverId = parsed.discord.serverId
    if parsed.discord.channelId.len > 0:
      result.discord.channelId = parsed.discord.channelId
    if parsed.discord.allowedUserIds.len > 0:
      result.discord.allowedUserIds = parsed.discord.allowedUserIds
  if raw.contains("\"mattermost\""):
    result.mattermost.enabled = parsed.mattermost.enabled
    if parsed.mattermost.url.len > 0:
      result.mattermost.url = parsed.mattermost.url
    if parsed.mattermost.channelId.len > 0:
      result.mattermost.channelId = parsed.mattermost.channelId
    if parsed.mattermost.allowedUserIds.len > 0:
      result.mattermost.allowedUserIds = parsed.mattermost.allowedUserIds
  if raw.contains("\"loop\""):
    result.loop.enabled = parsed.loop.enabled
    if parsed.loop.feedback.len > 0:
      result.loop.feedback = parsed.loop.feedback
    if parsed.loop.goal.len > 0:
      result.loop.goal = parsed.loop.goal
    if parsed.loop.maxIterations > 0:
      result.loop.maxIterations = parsed.loop.maxIterations
    if parsed.loop.feedbackTimeoutMs > 0:
      result.loop.feedbackTimeoutMs = parsed.loop.feedbackTimeoutMs
  if raw.contains("\"dashboard\""):
    if parsed.dashboard.host.len > 0:
      result.dashboard.host = parsed.dashboard.host
    if parsed.dashboard.port > 0:
      result.dashboard.port = parsed.dashboard.port
  if raw.contains("\"remoteSync\""):
    result.remoteSync.enabled = parsed.remoteSync.enabled
    if parsed.remoteSync.primaryRemote.len > 0:
      result.remoteSync.primaryRemote = parsed.remoteSync.primaryRemote
    if parsed.remoteSync.remotes.len > 0:
      result.remoteSync.remotes = parsed.remoteSync.remotes
    if parsed.remoteSync.syncIntervalSeconds > 0:
      result.remoteSync.syncIntervalSeconds = parsed.remoteSync.syncIntervalSeconds
  if raw.contains("\"syncAgentsMd\""):
    result.syncAgentsMd = parsed.syncAgentsMd
  if parsed.logLevel.len > 0:
    result.logLevel = parsed.logLevel
  if parsed.fileLogLevel.len > 0:
    result.fileLogLevel = parsed.fileLogLevel
  let envLogLevel = getEnv("SCRIPTORIUM_LOG_LEVEL")
  if envLogLevel.len > 0:
    result.logLevel = envLogLevel
  let envFileLogLevel = getEnv("SCRIPTORIUM_FILE_LOG_LEVEL")
  if envFileLogLevel.len > 0:
    result.fileLogLevel = envFileLogLevel
