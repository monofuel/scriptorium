import
  std/strutils,
  scriptorium/[agent_runner, config, intent_classifier, shared_state]

proc testParseIntentIgnore() =
  doAssert parseIntent("ignore") == intentIgnore
  doAssert parseIntent("  ignore  ") == intentIgnore
  doAssert parseIntent("IGNORE") == intentIgnore
  echo "[OK] parseIntent ignore"

proc testParseIntentChat() =
  doAssert parseIntent("chat") == intentChat
  doAssert parseIntent("  Chat\n") == intentChat
  echo "[OK] parseIntent chat"

proc testParseIntentAsk() =
  doAssert parseIntent("ask") == intentAsk
  doAssert parseIntent("ASK") == intentAsk
  echo "[OK] parseIntent ask"

proc testParseIntentPlan() =
  doAssert parseIntent("plan") == intentPlan
  doAssert parseIntent("Plan") == intentPlan
  echo "[OK] parseIntent plan"

proc testParseIntentDo() =
  doAssert parseIntent("do") == intentDo
  doAssert parseIntent("DO") == intentDo
  echo "[OK] parseIntent do"

proc testParseIntentFallback() =
  ## Unrecognized output falls back to intentAsk (safe read-only).
  doAssert parseIntent("unknown") == intentAsk
  doAssert parseIntent("") == intentAsk
  doAssert parseIntent("maybe plan or ask") == intentAsk
  echo "[OK] parseIntent fallback to ask"

proc testParseIntentMultiWord() =
  ## Only the first word matters.
  doAssert parseIntent("plan some extra text") == intentPlan
  doAssert parseIntent("do something") == intentDo
  echo "[OK] parseIntent multi-word takes first"

proc testBuildClassifierPromptWithDevops() =
  let prompt = buildClassifierPrompt("hello", @[], "testuser", devopsEnabled = true)
  doAssert "ignore" in prompt
  doAssert "chat" in prompt
  doAssert "ask" in prompt
  doAssert "plan" in prompt
  doAssert "do:" in prompt or "deploy" in prompt
  doAssert "testuser" in prompt
  doAssert "hello" in prompt
  echo "[OK] buildClassifierPrompt includes do intent when devops enabled"

proc testBuildClassifierPromptWithoutDevops() =
  let prompt = buildClassifierPrompt("hello", @[], "testuser", devopsEnabled = false)
  doAssert "ignore" in prompt
  doAssert "chat" in prompt
  doAssert "ask" in prompt
  doAssert "plan" in prompt
  doAssert "deploy" notin prompt
  doAssert "testuser" in prompt
  echo "[OK] buildClassifierPrompt excludes do intent when devops disabled"

proc testBuildClassifierPromptWithHistory() =
  let history = @[
    PlanTurn(role: "alice", text: "what's the status?"),
    PlanTurn(role: "architect", text: "all tickets done"),
  ]
  let prompt = buildClassifierPrompt("thanks!", history, "alice", devopsEnabled = false)
  doAssert "alice" in prompt
  doAssert "what's the status?" in prompt
  doAssert "all tickets done" in prompt
  doAssert "thanks!" in prompt
  echo "[OK] buildClassifierPrompt includes history"

proc testChatIntentEnumValues() =
  ## Verify enum string values match expected keywords.
  doAssert $intentIgnore == "ignore"
  doAssert $intentChat == "chat"
  doAssert $intentAsk == "ask"
  doAssert $intentPlan == "plan"
  doAssert $intentDo == "do"
  echo "[OK] ChatIntent enum string values"

proc testClassifyIntentWithMockRunner() =
  ## Verify classifyIntent passes config to the runner and parses the response.
  let mockRunner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
    doAssert request.model.len > 0, "model must be set in AgentRunRequest"
    doAssert request.model == "test-model"
    result = AgentRunResult(lastMessage: "plan")
  let cfg = AgentConfig(model: "test-model", harness: harnessClaudeCode)
  let intent = classifyIntent(mockRunner, "/tmp", "create a website", @[], "testuser", true, cfg)
  doAssert intent == intentPlan
  echo "[OK] classifyIntent passes config and parses response"

proc testClassifyIntentFallbackOnError() =
  ## Verify classifyIntent returns intentAsk on runner failure.
  let failRunner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
    raise newException(ValueError, "simulated failure")
  let cfg = AgentConfig(model: "test-model", harness: harnessClaudeCode)
  let intent = classifyIntent(failRunner, "/tmp", "hello", @[], "testuser", true, cfg)
  doAssert intent == intentAsk
  echo "[OK] classifyIntent falls back to ask on error"

proc testClassifyIntentPassesTimeouts() =
  ## Verify classifyIntent forwards timeout config to the runner.
  let mockRunner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
    doAssert request.noOutputTimeoutMs == 30000
    doAssert request.hardTimeoutMs == 60000
    result = AgentRunResult(lastMessage: "ignore")
  let cfg = AgentConfig(model: "test-model", harness: harnessClaudeCode, noOutputTimeout: 30000, hardTimeout: 60000)
  let intent = classifyIntent(mockRunner, "/tmp", "hey bob", @[], "testuser", false, cfg)
  doAssert intent == intentIgnore
  echo "[OK] classifyIntent forwards timeout config"

when isMainModule:
  testParseIntentIgnore()
  testParseIntentChat()
  testParseIntentAsk()
  testParseIntentPlan()
  testParseIntentDo()
  testParseIntentFallback()
  testParseIntentMultiWord()
  testBuildClassifierPromptWithDevops()
  testBuildClassifierPromptWithoutDevops()
  testBuildClassifierPromptWithHistory()
  testChatIntentEnumValues()
  testClassifyIntentWithMockRunner()
  testClassifyIntentFallbackOnError()
  testClassifyIntentPassesTimeouts()
