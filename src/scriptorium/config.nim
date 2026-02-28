import
  std/[os, strutils],
  jsony

const
  ConfigFile = "scriptorium.json"
  DefaultArchitectModel = "codex-fake-unit-test-model"
  DefaultCodingModel = "codex-fake-unit-test-model"
  DefaultManagerModel = "codex-fake-unit-test-model"
  DefaultArchitectReasoningEffort = ""
  DefaultCodingReasoningEffort = ""
  DefaultManagerReasoningEffort = ""

type
  Harness* = enum
    harnessClaudeCode = "claude-code"
    harnessCodex = "codex"
    harnessTypoi = "typoi"

  Models* = object
    architect*: string
    coding*: string
    manager*: string

  ReasoningEffort* = object
    architect*: string
    coding*: string
    manager*: string

  Endpoints* = object
    local*: string

  Config* = object
    models*: Models
    reasoningEffort*: ReasoningEffort
    endpoints*: Endpoints

proc defaultConfig*(): Config =
  ## Return a Config populated with default values.
  Config(
    models: Models(
      architect: DefaultArchitectModel,
      coding: DefaultCodingModel,
      manager: DefaultManagerModel,
    ),
    reasoningEffort: ReasoningEffort(
      architect: DefaultArchitectReasoningEffort,
      coding: DefaultCodingReasoningEffort,
      manager: DefaultManagerReasoningEffort,
    ),
    endpoints: Endpoints(
      local: "",
    ),
  )

proc harness*(model: string): Harness =
  ## Determine which agent harness to use for a given model name.
  if model.startsWith("claude-"):
    harnessClaudeCode
  elif model.startsWith("codex-") or model.startsWith("gpt-"):
    harnessCodex
  else:
    harnessTypoi

proc loadConfig*(repoPath: string): Config =
  ## Load scriptorium.json from repoPath, falling back to defaults for missing fields.
  let path = repoPath / ConfigFile
  if not fileExists(path):
    return defaultConfig()
  let raw = readFile(path)
  result = defaultConfig()
  let parsed = fromJson(raw, Config)
  if parsed.models.architect.len > 0:
    result.models.architect = parsed.models.architect
  if parsed.models.coding.len > 0:
    result.models.coding = parsed.models.coding
  if parsed.models.manager.len > 0:
    result.models.manager = parsed.models.manager
  if parsed.reasoningEffort.architect.len > 0:
    result.reasoningEffort.architect = parsed.reasoningEffort.architect
  if parsed.reasoningEffort.coding.len > 0:
    result.reasoningEffort.coding = parsed.reasoningEffort.coding
  if parsed.reasoningEffort.manager.len > 0:
    result.reasoningEffort.manager = parsed.reasoningEffort.manager
  if parsed.endpoints.local.len > 0:
    result.endpoints.local = parsed.endpoints.local
