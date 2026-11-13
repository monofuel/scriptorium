import
  ./[acp_runtime, agent_runner_types, common]

export agent_runner_types, acp_runtime

type
  ConversationRunner* = ref object
    runner*: AgentRunner
    conversation: AgentConversation

proc runAgent*(request: AgentRunRequest): AgentRunResult =
  ## Bound transient retries centrally while retaining a native conversation.
  var conversation: AgentConversation
  defer: conversation.close()
  var
    turn = request
    attempts = 0
    bytes = 0
  while attempts < max(request.maxAttempts, 1):
    turn.attempt = max(request.attempt, 1) + attempts
    result = runInConversation(conversation, turn)
    inc attempts
    bytes += result.outputBytes
    if result.failureKind notin {failureTimeout, failureTransport}: break
    if result.failureKind == failureTransport: conversation.close()
    if not request.continuationPromptBuilder.isNil:
      turn.prompt = request.continuationPromptBuilder(request.workingDir) & "\n" & request.prompt
    elif request.continuationPrompt.len > 0:
      turn.prompt = request.continuationPrompt
  result.attemptCount = attempts
  result.outputBytes = bytes

proc requireAgentCompleted*(response: AgentRunResult) =
  ## Fail explicitly when a command did not complete its ACP operation.
  if response.exitCode != 0:
    raise newException(IOError, "ACP operation failed (" & $response.failureKind &
      "): " & response.errorMessage & "; transcript: " & response.logFile)

proc newConversationRunner*(fallback: AgentRunner, resumeSessionId = "",
    cancellationRequested: CancellationCheck = nil): ConversationRunner =
  ## Reuse native sessions while retaining injected runners for isolated tests.
  new(result)
  let state = result
  if fallback == runAgent:
    state.runner = proc(request: AgentRunRequest): AgentRunResult =
      ## Keep one compatible conversation on the calling application thread.
      var configured = request
      configured.resumeSessionId = resumeSessionId
      if not cancellationRequested.isNil:
        configured.cancellationRequested = cancellationRequested
      runInConversation(state.conversation, configured)
  else:
    state.runner = fallback

proc close*(state: ConversationRunner) =
  ## Release the native connection and the callback's captured ownership cycle.
  if state.isNil: return
  state.conversation.close()
  state.runner = nil
