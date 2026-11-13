## Integration tests for intent classification with a real LLM.

import
  std/[os, strformat],
  scriptorium/[agent_runner, config, intent_classifier, shared_state],
  ./support/live_integration_support

proc testDoIntentBumpConfig() =
  ## Classify "Would you kindly bump maxAgents in scriptorium.json to 4?" as do.
  doAssert hasAgentAuth(),
    "Agent authentication is required"

  let model = integrationModel()
  let cfg = AgentConfig(model: model, harness: integrationHarness(), acpAgent: profileName(integrationHarness()))
  let message = "Would you kindly bump maxAgents in scriptorium.json to 4?"
  let history: seq[PlanTurn] = @[]
  let intent = classifyIntent(runAgent, "/tmp", message, history, "testuser", true, cfg)
  let intentStr = $intent
  doAssert intent == intentDo,
    &"Expected 'do' for config change request, got '{intentStr}'"
  echo "[OK] classify 'bump maxAgents in scriptorium.json to 4' as do"

when isMainModule:
  testDoIntentBumpConfig()
