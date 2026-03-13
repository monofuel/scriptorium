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
  DefaultModel = "codex-fake-unit-test-model"
  DefaultHarness = harnessCodex
  DefaultReasoningEffort = ""

type
  AgentConfig* = object
    harness*: Harness
    model*: string
    reasoningEffort*: string

  AgentConfigs* = object
    architect*: AgentConfig
    coding*: AgentConfig
    manager*: AgentConfig
    reviewer*: AgentConfig

  Endpoints* = object
    local*: string

  ConcurrencyConfig* = object
    maxAgents*: int
    tokenBudgetMB*: int

  TimeoutConfig* = object
    codingAgentHardTimeoutMs*: int
    codingAgentNoOutputTimeoutMs*: int
    codingAgentMaxAttempts*: int

  Config* = object
    agents*: AgentConfigs
    endpoints*: Endpoints
    concurrency*: ConcurrencyConfig
    timeouts*: TimeoutConfig
    logLevel*: string
    fileLogLevel*: string

proc defaultAgentConfig(): AgentConfig =
  ## Return an AgentConfig populated with default values.
  AgentConfig(
    harness: DefaultHarness,
    model: DefaultModel,
    reasoningEffort: DefaultReasoningEffort,
  )

proc defaultConfig*(): Config =
  ## Return a Config populated with default values.
  Config(
    agents: AgentConfigs(
      architect: defaultAgentConfig(),
      coding: defaultAgentConfig(),
      manager: defaultAgentConfig(),
      reviewer: defaultAgentConfig(),
    ),
    endpoints: Endpoints(
      local: "",
    ),
    concurrency: ConcurrencyConfig(
      maxAgents: 1,
      tokenBudgetMB: 0,
    ),
    timeouts: TimeoutConfig(
      codingAgentHardTimeoutMs: 14_400_000,
      codingAgentNoOutputTimeoutMs: 300_000,
      codingAgentMaxAttempts: 5,
    ),
  )

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
  if parsed.timeouts.codingAgentMaxAttempts > 0:
    result.timeouts.codingAgentMaxAttempts = parsed.timeouts.codingAgentMaxAttempts
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
