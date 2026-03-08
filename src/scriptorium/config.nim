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

  Endpoints* = object
    local*: string

  Config* = object
    agents*: AgentConfigs
    endpoints*: Endpoints
    logLevel*: string

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
    ),
    endpoints: Endpoints(
      local: "",
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
  if parsed.endpoints.local.len > 0:
    result.endpoints.local = parsed.endpoints.local
  if parsed.logLevel.len > 0:
    result.logLevel = parsed.logLevel
  let envLogLevel = getEnv("SCRIPTORIUM_LOG_LEVEL")
  if envLogLevel.len > 0:
    result.logLevel = envLogLevel
