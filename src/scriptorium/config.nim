import
  std/[json, os, strutils, tables],
  jsony

type
  Harness* = enum
    harnessClaudeCode = "claude-code"
    harnessCodex = "codex"
    harnessTypoi = "typoi"
    harnessGrokBuild = "grok-build"
    harnessHermes = "hermes"

const
  ConfigFile = "scriptorium.json"
  DefaultArchitectModel = ""
  DefaultCodingModel = ""
  DefaultManagerModel = ""
  DefaultReviewerModel = ""
  DefaultAuditModel* = ""
  DefaultHarness = harnessClaudeCode
  DefaultReasoningEffort = ""
  DefaultLocalEndpoint = "http://127.0.0.1:8097"
  DefaultDashboardPort = 8098
  DefaultDashboardHost = "127.0.0.1"
  DefaultFeedbackTimeoutMs* = 7_200_000

type
  AcpAgentProfile* = object
    command*: string
    args*: seq[string]
    readOnlyArgs*: seq[string]
    env*: Table[string, string]
    modelOption*: string
    effortOption*: string
    readOnlyMode*: string
    writeMode*: string
    authMethod*: string

  AgentConfig* = object
    acpAgent*: string
    configOptions*: Table[string, JsonNode]
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
    serverId*: string
    channelId*: string
    allowedUserIds*: seq[string]
    allowedUsers*: seq[string]
    chatHistoryCount*: int

  MattermostConfig* = object
    url*: string
    channelId*: string
    allowedUserIds*: seq[string]
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
    outputBudgetMB*: int
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
    acpAgents*: Table[string, AcpAgentProfile]
    endpoints*: Endpoints
    concurrency*: ConcurrencyConfig
    timeouts*: TimeoutConfig
    discord*: DiscordConfig
    mattermost*: MattermostConfig
    loop*: LoopConfig
    dashboard*: DashboardConfig
    devops*: DevopsConfig
    remoteSync*: RemoteSyncConfig
    diskSpaceMinGB*: int
    syncAgentsMd*: bool
    logLevel*: string
    fileLogLevel*: string

proc defaultAcpAgents*(): Table[string, AcpAgentProfile] =
  ## Define launch profiles for the three supported ACP agents.
  result["codex"] = AcpAgentProfile(command: "codex-acp",
    readOnlyMode: "read-only", writeMode: "agent",
    env: {"NO_BROWSER": "1"}.toTable())
  result["claude"] = AcpAgentProfile(command: "claude-agent-acp",
    readOnlyMode: "plan", writeMode: "default",
    env: {"CLAUDE_AGENT_ACP_PROTOCOL": "v1"}.toTable())
  result["grok"] = AcpAgentProfile(command: "grok",
    args: @["--no-auto-update", "agent", "--no-leader", "stdio"],
    readOnlyArgs: @["--permission-mode", "dontAsk", "--deny", "Edit",
      "--deny", "Bash", "--deny", "MCPTool", "--no-subagents"],
    readOnlyMode: "plan", writeMode: "default")

proc profileName*(harness: Harness): string =
  ## Translate a supported legacy harness identifier to an ACP profile.
  case harness
  of harnessCodex: "codex"
  of harnessClaudeCode: "claude"
  of harnessGrokBuild: "grok"
  of harnessTypoi, harnessHermes:
    raise newException(ValueError, "The " & $harness &
      " runner was retired in v20. Configure a named acpAgents profile and select acpAgent.")

proc resolveAcpProfile*(cfg: Config, agent: AgentConfig): AcpAgentProfile =
  ## Resolve one role to its configured ACP executable and launch settings.
  let name = if agent.acpAgent.len > 0: agent.acpAgent else: profileName(agent.harness)
  if not cfg.acpAgents.hasKey(name):
    raise newException(ValueError, "Unknown ACP agent profile: " & name)
  result = cfg.acpAgents[name]
  if result.command.strip().len == 0:
    raise newException(ValueError, "ACP agent profile requires command: " & name)

proc defaultAgentConfig(model: string, hardTimeout: int = 0,
    noOutputTimeout: int = 0, progressTimeout: int = 0): AgentConfig =
  ## Return an AgentConfig populated with default values for a given model and timeouts.
  AgentConfig(
    acpAgent: "claude",
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
    acpAgents: defaultAcpAgents(),
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
    discord: DiscordConfig(serverId: "", channelId: "", allowedUserIds: @[], allowedUsers: @[], chatHistoryCount: 8),
    mattermost: MattermostConfig(url: "", channelId: "", allowedUserIds: @[], allowedUsers: @[], chatHistoryCount: 8),
    loop: LoopConfig(enabled: false, feedback: "", goal: "", maxIterations: 0, feedbackTimeoutMs: DefaultFeedbackTimeoutMs),
    devops: DevopsConfig(enabled: false),
    dashboard: DashboardConfig(host: DefaultDashboardHost, port: DefaultDashboardPort),
    diskSpaceMinGB: 20,
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
  of "claude-opus-5": "us.anthropic.claude-opus-5-v1"
  of "claude-opus-4-6": "us.anthropic.claude-opus-4-6-v1"
  of "claude-sonnet-5": "us.anthropic.claude-sonnet-5-v1"
  of "claude-sonnet-4-6": "us.anthropic.claude-sonnet-4-6"
  of "claude-haiku-4-5-20251001": "us.anthropic.claude-haiku-4-5-20251001-v1:0"
  else: model

proc inferHarness*(model: string): Harness =
  ## Infer a harness from a model name prefix. Intended for test convenience only.
  if model.startsWith("claude-"):
    harnessClaudeCode
  elif model.startsWith("codex-") or model.startsWith("gpt-"):
    harnessCodex
  elif model.startsWith("grok-4") or model.startsWith("grok-build"):
    harnessGrokBuild
  else:
    harnessTypoi

proc deepMerge(defaults: JsonNode, user: JsonNode): JsonNode =
  ## Merge user values over defaults, preserving unknown user keys.
  if defaults.kind == JObject and user.kind == JObject:
    result = copy(defaults)
    for key, defaultVal in defaults.pairs:
      if key in user:
        result[key] = deepMerge(defaultVal, user[key])
    for key, userVal in user.pairs:
      if key notin result:
        result[key] = copy(userVal)
  else:
    result = copy(user)

proc fixupHarnesses(cfg: var Config, userJson: JsonNode) =
  ## Translate legacy routing while giving explicit ACP profiles precedence.
  template fixup(agent: var AgentConfig, agentKey: string) =
    if userJson.hasKey("agents") and userJson["agents"].hasKey(agentKey):
      let aj = userJson["agents"][agentKey]
      if aj.hasKey("acpAgent"):
        if agent.acpAgent.len == 0:
          agent.acpAgent = profileName(agent.harness)
        case agent.acpAgent
        of "codex": agent.harness = harnessCodex
        of "claude": agent.harness = harnessClaudeCode
        of "grok": agent.harness = harnessGrokBuild
        else: discard
      elif aj.hasKey("harness"):
        agent.acpAgent = profileName(agent.harness)
        stderr.writeLine("scriptorium: agents." & agentKey &
          ".harness is deprecated; use acpAgent: " & agent.acpAgent)
      elif aj.hasKey("model") and agent.model.len > 0:
        let inferred = inferHarness(agent.model)
        if inferred notin {harnessTypoi, harnessHermes}:
          agent.harness = inferred
          agent.acpAgent = profileName(inferred)
      discard cfg.resolveAcpProfile(agent)
  fixup(cfg.agents.architect, "architect")
  fixup(cfg.agents.coding, "coding")
  fixup(cfg.agents.manager, "manager")
  fixup(cfg.agents.reviewer, "reviewer")
  fixup(cfg.agents.audit, "audit")

proc backfillEmptyFields(cfg: var Config) =
  ## Restore defaults for fields where an empty value is never meaningful.
  if cfg.endpoints.local.len == 0:
    cfg.endpoints.local = DefaultLocalEndpoint

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
  backfillEmptyFields(result)
  let concurrency = userJson.getOrDefault("concurrency")
  if not concurrency.isNil and concurrency.kind == JObject and not concurrency.hasKey("outputBudgetMB"):
    result.concurrency.outputBudgetMB = result.concurrency.tokenBudgetMB
  if result.concurrency.maxAgents < 1 or result.concurrency.outputBudgetMB < 0:
    raise newException(ValueError, "Concurrency requires maxAgents >= 1 and outputBudgetMB >= 0")
  # Apply env overrides.
  let envLogLevel = getEnv("SCRIPTORIUM_LOG_LEVEL")
  if envLogLevel.len > 0:
    result.logLevel = envLogLevel
  let envFileLogLevel = getEnv("SCRIPTORIUM_FILE_LOG_LEVEL")
  if envFileLogLevel.len > 0:
    result.fileLogLevel = envFileLogLevel

proc normalizeConfig*(repoPath: string) =
  ## Load raw JSON, deep-merge with defaults, and write back directly.
  ## Preserves unknown user keys that are not in the Config struct.
  let path = repoPath / ConfigFile
  if not fileExists(path):
    return
  let raw = readFile(path)
  let userJson = parseJson(raw)
  let defaultJson = parseJson(defaultConfig().toJson())
  let merged = deepMerge(defaultJson, userJson)
  let loaded = loadConfig(repoPath)
  for key in ["architect", "coding", "manager", "reviewer", "audit"]:
    let translated = parseJson(loaded.toJson())["agents"][key]
    merged["agents"][key]["acpAgent"] = translated["acpAgent"]
  merged["concurrency"]["outputBudgetMB"] = %loaded.concurrency.outputBudgetMB
  writeFile(path, merged.pretty() & "\n")
