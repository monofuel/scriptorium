import
  std/[json, monotimes, options, os, strutils, tables, tempfiles, times, unittest],
  acport,
  scriptorium/[agent_runner, config, mcp_server, orchestrator]

const
  AcpBackend {.strdefine.} = "codex"
  backend = AcpBackend

let
  artifactRoot = absolutePath(".build/live/" & backend)

doAssert backend in ["codex", "claude", "grok"], "Select codex, claude or grok as an argument"
createDir(artifactRoot)

proc liveRequest(directory, text: string): AgentRunRequest =
  ## Run a real pinned agent without replacing its protocol or model dependency.
  AgentRunRequest(prompt: text, workingDir: directory, acpAgent: backend,
    profile: defaultAcpAgents()[backend], logRoot: absolutePath(".build/live/" & backend),
    sessionRoot: directory / ".scriptorium" / "sessions",
    ticketId: directory.extractFilename(), noOutputTimeoutMs: 120_000,
    hardTimeoutMs: 300_000)

proc requireCompleted(response: AgentRunResult) =
  ## Fail with concrete diagnostics rather than hiding provider or setup failures.
  doAssert response.exitCode == 0,
    $response.failureKind & ": " & response.errorMessage & "; transcript: " & response.logFile

type ConcurrentArgs = tuple[directory, nonce: string, results: ptr Channel[string]]

proc executeConcurrentConversation(args: ConcurrentArgs) =
  ## Exercise two real ACP connections owned by separate application threads.
  try:
    var request = liveRequest(args.directory, "Write private.txt containing exactly " &
      args.nonce & ". Remember that word. Reply OK.")
    let owner = getThreadId()
    var callbacksOwned = true
    request.onEvent = proc(event: AgentStreamEvent) =
      ## Check callbacks do not cross between owning application threads.
      if getThreadId() != owner: callbacksOwned = false
    let conversation = openConversation(request)
    defer: conversation.close()
    let first = conversation.runTurn(request)
    first.requireCompleted()
    request.prompt = "What exact word did you write? Reply with only that word."
    request.attempt = 2
    let second = conversation.runTurn(request)
    second.requireCompleted()
    args.results[].send($(%*{"sessionId": first.sessionId, "reply": second.lastMessage,
      "callbacksOwned": callbacksOwned}))
  except CatchableError as error:
    args.results[].send($(%*{"error": error.msg}))

proc runConcurrentConversation(args: ConcurrentArgs) {.thread.} =
  ## Own every managed value and callback inside this worker's heap.
  {.cast(gcsafe).}:
    executeConcurrentConversation(args)

suite "real ACP agent: " & backend:
  test "streaming, explicit settings, native turns and persisted recovery":
    let directory = createTempDir("scriptorium-acp-live-", "")
    defer: removeDir(directory)
    let nonce = "remember-" & $getCurrentProcessId()
    var request = liveRequest(directory, "Remember the exact word " & nonce & ". Reply with OK. Do not use tools.")
    var messages = 0
    request.onEvent = proc(event: AgentStreamEvent) =
      ## Count real structured assistant updates.
      if event.kind == agentEventMessage: inc messages
    let conversation = openConversation(request)
    defer: conversation.close()
    let first = conversation.runTurn(request)
    first.requireCompleted()
    check messages > 0
    let catalog = conversation.configurationOptions()
    for option in catalog:
      if option.category.get("") == "model": request.model = option.currentValue.stringValue
      if option.category.get("") == "thought_level" and option.currentValue.kind == stringConfigValue:
        request.reasoningEffort = option.currentValue.stringValue
    # Changing application identity is deliberately forbidden inside a conversation.
    var secondRequest = liveRequest(directory, "What exact word did I ask you to remember? Reply with only that word.")
    secondRequest.attempt = 2
    let second = conversation.runTurn(secondRequest)
    second.requireCompleted()
    check nonce in second.lastMessage
    conversation.close()
    request.prompt = "Reply with SETTINGS_OK. Do not use tools."
    request.attempt = 3
    runAgent(request).requireCompleted()
    secondRequest.restoreSession = true
    secondRequest.attempt = 4
    let restored = runAgent(secondRequest)
    restored.requireCompleted()
    check restored.sessionId == first.sessionId
    check nonce in restored.lastMessage

  test "read-only access cannot write project files":
    let directory = createTempDir("scriptorium-acp-readonly-", "")
    defer: removeDir(directory)
    var request = liveRequest(directory,
      "Try to write forbidden.txt containing forbidden using your file tools. Report the permission result, then stop.")
    request.accessPolicy = accessReadOnly
    let response = runAgent(request)
    doAssert not fileExists(directory / "forbidden.txt"), "Read-only agent modified the repository"
    doAssert response.failureKind in {failureNone, failureRefused, failureCancelled},
      $response.failureKind & ": " & response.errorMessage

  test "writes and submit_pr use real tools and fresh scoped MCP after restart":
    let directory = createTempDir("scriptorium-acp-mcp-", "")
    defer: removeDir(directory)
    let
      port = 31000 + (getCurrentProcessId() mod 1000)
      endpoint = "http://127.0.0.1:" & $port
      host = createAgentMcpHost()
    var serverThread: Thread[ServerThreadArgs]
    createThread(serverThread, runHttpServer, (host, "127.0.0.1", port))
    waitForServerReady("127.0.0.1", port)
    defer:
      signalServerShutdown()
      joinThread(serverThread)
    let firstMcp = newCodingMcpSession(endpoint, "live-ticket", "live-branch", directory)
    defer: unregisterAgentMcpSession(firstMcp)
    let nonce = "acp-mcp-" & $getCurrentProcessId()
    var request = liveRequest(directory,
      "Write proof.txt containing exactly " & nonce & ". Then call the scriptorium submit_pr tool with summary " & nonce & ". Do not merely describe the tool call.")
    request.mcpEndpoint = firstMcp.endpoint
    request.conversationKey = "live-ticket"
    let first = runAgent(request)
    first.requireCompleted()
    check readFile(directory / "proof.txt").strip() == nonce
    check codingSubmission(firstMcp) == (called: true, summary: nonce)
    check "tools/call" in mcpRequestMethods(firstMcp)
    acknowledgeCodingSubmission(firstMcp)
    unregisterAgentMcpSession(firstMcp)
    let secondMcp = newCodingMcpSession(endpoint, "live-ticket", "live-branch", directory)
    defer: unregisterAgentMcpSession(secondMcp)
    request.mcpEndpoint = secondMcp.endpoint
    request.restoreSession = true
    request.attempt = 2
    request.prompt = "Call the scriptorium submit_pr tool again with summary rebound-" & nonce & ". Do not write files."
    let restored = runAgent(request)
    restored.requireCompleted()
    check restored.sessionId == first.sessionId
    check codingSubmission(secondMcp) == (called: true, summary: "rebound-" & nonce)

  test "cancellation settles and another turn succeeds on the same connection":
    let directory = createTempDir("scriptorium-acp-cancel-", "")
    defer: removeDir(directory)
    var
      toolStarted = false
      toolTime = getMonoTime()
      request = liveRequest(directory, "Run sleep 60 using your shell tool and wait for it. Do not run any other commands.")
    request.onEvent = proc(event: AgentStreamEvent) =
      ## Cancel only after observing the real command start.
      if event.kind == agentEventTool and not toolStarted:
        toolStarted = true
        toolTime = getMonoTime()
    request.cancellationRequested = proc(): bool =
      ## Give the running command a brief interval before cancellation.
      toolStarted and (getMonoTime() - toolTime).inMilliseconds > 500
    let conversation = openConversation(request)
    defer: conversation.close()
    let response = conversation.runTurn(request)
    check toolStarted
    check response.cancelled
    request.cancellationRequested = nil
    request.prompt = "Reply exactly AFTER_CANCEL. Do not use tools."
    request.attempt = 2
    let after = conversation.runTurn(request)
    after.requireCompleted()
    check "AFTER_CANCEL" in after.lastMessage

  test "concurrent connections isolate callbacks, worktrees and conversations":
    let directory = createTempDir("scriptorium-acp-parallel-", "")
    defer: removeDir(directory)
    let
      left = directory / "left"
      right = directory / "right"
      nonce = $getCurrentProcessId()
    createDir(left)
    createDir(right)
    var
      results: Channel[string]
      threads: array[2, Thread[ConcurrentArgs]]
    results.open()
    defer: results.close()
    createThread(threads[0], runConcurrentConversation, (left, "left-" & nonce, addr results))
    createThread(threads[1], runConcurrentConversation, (right, "right-" & nonce, addr results))
    joinThreads(threads)
    let
      first = parseJson(results.recv())
      second = parseJson(results.recv())
    doAssert not first.hasKey("error"), $first
    doAssert not second.hasKey("error"), $second
    check first["sessionId"].getStr() != second["sessionId"].getStr()
    check first["callbacksOwned"].getBool() and second["callbacksOwned"].getBool()
    check first["reply"].getStr() != second["reply"].getStr()
    check readFile(left / "private.txt").strip() == "left-" & nonce
    check readFile(right / "private.txt").strip() == "right-" & nonce
