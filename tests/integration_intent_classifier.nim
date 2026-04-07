## Integration tests for intent classification with a real LLM.

import
  std/[os, strformat],
  scriptorium/[agent_runner, config, intent_classifier, shared_state]

const
  DefaultIntegrationModel = "claude-opus-4-6"

proc integrationModel(): string =
  ## Return the configured integration model, or the default model.
  result = getEnv("SCRIPTORIUM_TEST_MODEL", DefaultIntegrationModel)

proc hasClaudeAuth(): bool =
  ## Return true when Claude Code auth is available (API key, OAuth, or Bedrock).
  let hasApiKey = getEnv("ANTHROPIC_API_KEY", "").len > 0
  let hasOauth = fileExists(expandTilde("~/.claude/.credentials.json"))
  let hasBedrock = getEnv("CLAUDE_CODE_USE_BEDROCK", "").len > 0
  result = hasApiKey or hasOauth or hasBedrock

proc testDoIntentBumpConfig() =
  ## Classify "Would you kindly bump maxAgents in scriptorium.json to 4?" as do.
  doAssert hasClaudeAuth(),
    "Claude Code auth is required (ANTHROPIC_API_KEY, ~/.claude/.credentials.json, or CLAUDE_CODE_USE_BEDROCK)"

  let model = integrationModel()
  let cfg = AgentConfig(model: model, harness: harnessClaudeCode)
  let message = "Would you kindly bump maxAgents in scriptorium.json to 4?"
  let history: seq[PlanTurn] = @[]
  let intent = classifyIntent(runAgent, "/tmp", message, history, "testuser", true, cfg)
  let intentStr = $intent
  doAssert intent == intentDo,
    &"Expected 'do' for config change request, got '{intentStr}'"
  echo "[OK] classify 'bump maxAgents in scriptorium.json to 4' as do"

when isMainModule:
  testDoIntentBumpConfig()
