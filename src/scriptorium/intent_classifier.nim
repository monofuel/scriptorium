import
  std/[strformat, strutils],
  ./[agent_runner, config, prompt_catalog, shared_state]

type
  ChatIntent* = enum
    intentIgnore = "ignore"
    intentChat = "chat"
    intentAsk = "ask"
    intentPlan = "plan"
    intentDo = "do"

const
  DoIntentLine = "- do: A request to execute, deploy, configure, or build something on the system"

proc buildClassifierPrompt*(message: string, history: seq[PlanTurn],
                            username: string, devopsEnabled: bool): string =
  ## Build the intent classification prompt from the template.
  let doIntent = if devopsEnabled: DoIntentLine else: ""
  var chatHistory = ""
  if history.len > 0:
    for turn in history:
      chatHistory &= &"[{turn.role}]: {turn.text.strip()}\n"
  result = renderPromptTemplate(
    IntentClassifierTemplate,
    [
      (name: "DO_INTENT", value: doIntent),
      (name: "CHAT_HISTORY", value: chatHistory.strip()),
      (name: "USERNAME", value: username),
      (name: "USER_MESSAGE", value: message.strip()),
    ],
  )

proc parseIntent*(response: string): ChatIntent =
  ## Parse a single-word intent from agent output.
  ## Falls back to intentAsk (safe read-only default) for unrecognized output.
  let word = response.strip().toLowerAscii().split({' ', '\n', '\r', '\t'})[0]
  case word
  of "ignore": intentIgnore
  of "chat": intentChat
  of "ask": intentAsk
  of "plan": intentPlan
  of "do": intentDo
  else: intentAsk

proc classifyIntent*(runner: AgentRunner, repoPath: string,
                     message: string, history: seq[PlanTurn],
                     username: string, devopsEnabled: bool,
                     agentCfg: AgentConfig): ChatIntent =
  ## Classify a chat message intent using the configured agent runner.
  ## Returns intentAsk as a safe fallback on any error.
  {.cast(gcsafe).}:
    let prompt = buildClassifierPrompt(message, history, username, devopsEnabled)
    try:
      let agentResult = runner(AgentRunRequest(
        prompt: prompt,
        workingDir: repoPath,
        harness: agentCfg.harness,
        model: agentCfg.model,
        reasoningEffort: agentCfg.reasoningEffort,
        noOutputTimeoutMs: agentCfg.noOutputTimeout,
        hardTimeoutMs: agentCfg.hardTimeout,
      ))
      let output = agentResult.lastMessage.strip()
      let fallback = agentResult.stdout.strip()
      let text = if output.len > 0: output else: fallback
      parseIntent(text)
    except CatchableError as e:
      echo &"scriptorium: intent classification failed: {e.msg}"
      intentAsk
