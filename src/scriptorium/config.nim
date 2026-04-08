import
  std/[json, os, strutils],
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
    allowedUsers*: seq[string]
    chatHistoryCount*: int

  MattermostConfig* = object
    enabled*: bool
    url*: string
    channelId*: string
    allowedUsers*: seq[string]
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

  DevopsConfig* = object
    enabled*: bool

  Config* = object
    agents*: AgentConfigs
    endpoints*: Endpoints
    concurrency*: ConcurrencyConfig
    timeouts*: TimeoutConfig
    discord*: DiscordConfig
    mattermost*: MattermostConfig
    loop*: LoopConfig
    dashboard*: DashboardConfig
    devops*: DevopsConfig
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
      maxAgents: 4,
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
    discord: DiscordConfig(enabled: false, serverId: "", channelId: "", allowedUsers: @[], chatHistoryCount: 8),
    mattermost: MattermostConfig(enabled: false, url: "", channelId: "", allowedUsers: @[], chatHistoryCount: 8),
    loop: LoopConfig(enabled: false, feedback: "", goal: "", maxIterations: 0, feedbackTimeoutMs: DefaultFeedbackTimeoutMs),
    devops: DevopsConfig(enabled: false),
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

proc deepMerge(defaults: JsonNode, user: JsonNode): JsonNode =
  ## Merge user values over defaults. Only keys present in defaults are kept.
  if defaults.kind == JObject and user.kind == JObject:
    result = copy(defaults)
    for key, defaultVal in defaults.pairs:
      if key in user:
        result[key] = deepMerge(defaultVal, user[key])
  else:
    result = copy(user)

proc fixupHarnesses(cfg: var Config, userJson: JsonNode) =
  ## Infer harness from model when user set model but not harness.
  template fixup(agent: var AgentConfig, agentKey: string) =
    if userJson.hasKey("agents") and userJson["agents"].hasKey(agentKey):
      let aj = userJson["agents"][agentKey]
      if aj.hasKey("model") and not aj.hasKey("harness"):
        agent.harness = inferHarness(agent.model)
  fixup(cfg.agents.architect, "architect")
  fixup(cfg.agents.coding, "coding")
  fixup(cfg.agents.manager, "manager")
  fixup(cfg.agents.reviewer, "reviewer")
  fixup(cfg.agents.audit, "audit")

proc saveConfig*(repoPath: string, cfg: Config) =
  ## Write config as pretty-printed JSON.
  let path = repoPath / ConfigFile
  let jsonStr = parseJson(cfg.toJson()).pretty()
  writeFile(path, jsonStr & "\n")

proc loadConfig*(repoPath: string): Config =
  ## Load scriptorium.json, deep-merging with defaults. Read-only — does not write the file.
  ## Raises ValueError on invalid JSON with a clear recovery message.
  let path = repoPath / ConfigFile
  if not fileExists(path):
    return defaultConfig()
  let raw = readFile(path)
  var userJson: JsonNode
  try:
    userJson = parseJson(raw)
  except JsonParsingError:
    let msg = getCurrentExceptionMsg()
    raise newException(ValueError,
      "scriptorium.json is corrupted or not valid JSON: " & msg &
      ". Delete the file and run 'scriptorium init' to regenerate defaults.")
  let defaultJson = parseJson(defaultConfig().toJson())
  let merged = deepMerge(defaultJson, userJson)
  result = fromJson($merged, Config)
  fixupHarnesses(result, userJson)
  # Apply env overrides.
  let envLogLevel = getEnv("SCRIPTORIUM_LOG_LEVEL")
  if envLogLevel.len > 0:
    result.logLevel = envLogLevel
  let envFileLogLevel = getEnv("SCRIPTORIUM_FILE_LOG_LEVEL")
  if envFileLogLevel.len > 0:
    result.fileLogLevel = envFileLogLevel

proc normalizeConfig*(repoPath: string) =
  ## Load, merge with defaults, and write back the config file once.
  ## Call at startup to add new fields, remove old ones, and pretty-print.
  let path = repoPath / ConfigFile
  if not fileExists(path):
    return
  let cfg = loadConfig(repoPath)
  saveConfig(repoPath, cfg)
