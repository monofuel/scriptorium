import
  std/[json, options, os, osproc, strutils, tables, tempfiles, unittest],
  acport,
  scriptorium/[acp_permissions, agent_runner, agent_sessions, config, lock_management, prompt_builders, runtime_status]

let fixture = getTempDir() / ("scriptorium-acp-fixture-" & $getCurrentProcessId())
let compiler = getEnv("NIM", "nim")
let process = startProcess(compiler, args = @["c", "--hints:off", "--warnings:off",
  "-o:" & fixture, currentSourcePath().parentDir / "fixtures" / "acp_agent.nim"],
  options = {poUsePath, poParentStreams})
let compileExit = process.waitForExit()
process.close()
doAssert compileExit == 0, "Could not compile independent ACP unit fixture"

proc requestFor(directory, prompt: string): AgentRunRequest =
  ## Build a request that exercises real ACPort against an independent unit peer.
  AgentRunRequest(prompt: prompt, workingDir: directory, harness: harnessCodex,
    acpAgent: "codex", binary: fixture, ticketId: "unit",
    model: "fixture-model", reasoningEffort: "high", hardTimeoutMs: 5000,
    logRoot: directory / "logs", sessionRoot: directory / "sessions")

suite "shared ACP runner":
  test "historical invalid bytes fail raw ACP but explicit prompt projection completes":
    let directory = createTempDir("scriptorium-acp-utf8-", "")
    defer: removeDir(directory)
    let historical = "# Synthetic ticket\n\n## Agent Run\n\x86 retained original bytes"
    let invalid = runAgent(requestFor(directory, historical))
    check invalid.failureKind == failureProtocol
    check "Outgoing JSON must be UTF-8" in invalid.errorMessage
    let projected = buildCodingAgentPrompt(directory, directory, "tickets/in-progress/0003.md", historical)
    let completed = runAgent(requestFor(directory, projected))
    check completed.failureKind == failureNone
    check completed.exitCode == 0
    check completed.lastMessage.len > 0

  test "native activity is observed without changing conversation reuse or event forwarding":
    let directory = createTempDir("scriptorium-acp-activity-", "")
    defer: removeDir(directory)
    acquireOrchestratorPidGuard(directory)
    defer: releaseOrchestratorPidGuard(directory)
    installRuntimeActivityObserver(directory)
    defer: clearRuntimeActivityObserver()
    var request = requestFor(directory, "fixture:stream private-prompt-sentinel")
    request.activityRole = "manager"
    request.activityTask = "Plan regression tests"
    request.activityAreaId = "regression"
    request.profile = defaultAcpAgents()["codex"]
    request.profile.env["FIXTURE_LOG"] = directory / "peer.jsonl"
    let owner = getThreadId()
    var seen = 0
    request.onEvent = proc(event: AgentStreamEvent) =
      ## Observe an actual native call while preserving the original application callback.
      check getThreadId() == owner
      inc seen
      let state = readVerifiedActivity(directory).get()
      check state.active.len == 1
      check state.active[0].role == "manager"
      check state.active[0].model == "fixture-model"
      check state.active[0].reasoningEffort == "high"
    let conversation = newConversationRunner(runAgent)
    defer: conversation.close()
    let first = conversation.runner(request)
    check first.exitCode == 0
    check first.lastMessage == "stream-tail"
    request.prompt = "fixture:hello"
    let second = conversation.runner(request)
    check second.exitCode == 0
    check second.sessionId == first.sessionId
    check seen > 0
    let state = readVerifiedActivity(directory).get()
    check state.active.len == 0
    check state.recent.len == 2
    check state.recent[1].nativeSessionId == first.sessionId
    check state.recent[1].state == "completed"
    check "private-prompt-sentinel" notin readFile(runtimeActivityPath(directory))
    var sessionsCreated = 0
    for line in lines(directory / "peer.jsonl"):
      if parseJson(line){"method"}.getStr() == "session/new": inc sessionsCreated
    check sessionsCreated == 1

  test "activity snapshot I/O failure does not change the native result":
    let directory = createTempDir("scriptorium-acp-activity-io-", "")
    defer: removeDir(directory)
    acquireOrchestratorPidGuard(directory)
    defer: releaseOrchestratorPidGuard(directory)
    installRuntimeActivityObserver(directory)
    defer: clearRuntimeActivityObserver()
    removeFile(runtimeActivityPath(directory))
    createDir(runtimeActivityPath(directory))
    let response = runAgent(requestFor(directory, "fixture:hello"))
    check response.exitCode == 0
    check response.lastMessage == "hello-tail"
    check response.failureKind == failureNone
    check readVerifiedActivity(directory).isNone

  test "the final message excludes commentary that preceded tools":
    let directory = createTempDir("scriptorium-acp-final-", "")
    defer: removeDir(directory)
    writeFile(directory / "spec.md", "Synthetic specification.")
    let response = runAgent(requestFor(directory, "fixture:read-final"))
    check response.exitCode == 0
    check response.lastMessage == "Final answer: Synthetic specification."
    check "I will read" in response.transcriptText
    check response.failedTools.len == 0

  test "a denied permission and native cancellation retain their provenance":
    let directory = createTempDir("scriptorium-acp-denied-", "")
    defer: removeDir(directory)
    var request = requestFor(directory, "fixture:read-policy-cancel")
    request.accessPolicy = accessReadOnly
    let response = runAgent(request)
    check response.exitCode != 0
    check response.failureKind == failureCancelled
    check response.cancellationSource == "native"
    check response.deniedPermissions == 1
    check response.failedTools == @["read-spec"]
    check response.lastMessage == ""
    check "I will read" in response.transcriptText

  test "ordered callbacks stay on the caller thread and retain final chunks":
    let directory = createTempDir("scriptorium-acp-", "")
    defer: removeDir(directory)
    let owner = getThreadId()
    var request = requestFor(directory, "hello")
    var chunks: seq[string]
    request.onEvent = proc(event: AgentStreamEvent) =
      ## Verify application callbacks remain on their owning thread.
      check getThreadId() == owner
      if event.kind == agentEventMessage: chunks.add(event.text)
    let response = runAgent(request)
    check response.exitCode == 0
    check response.lastMessage == "hello-tail"
    check chunks == @["hello", "-tail"]
    check response.outputBytes > 0
    check response.stdout.len == 0
    check readFile(response.lastMessageFile) == response.lastMessage

  test "native turns reuse one session and resumed history is not a new reply":
    let directory = createTempDir("scriptorium-acp-", "")
    defer: removeDir(directory)
    var request = requestFor(directory, "first")
    let session = openConversation(request)
    let first = session.runTurn(request)
    request.prompt = "second"
    let second = session.runTurn(request)
    check first.sessionId == second.sessionId
    check second.lastMessage == "second-tail"
    session.close()
    request.restoreSession = true
    request.prompt = "third"
    let resumed = runAgent(request)
    check resumed.sessionId == first.sessionId
    check resumed.lastMessage == "third-tail"

  test "model and dependent effort are selected before prompting":
    let directory = createTempDir("scriptorium-acp-", "")
    defer: removeDir(directory)
    let response = runAgent(requestFor(directory, "settings"))
    check response.lastMessage == "fixture-model:high:agent-tail"

  test "read-only permissions reject writes":
    let directory = createTempDir("scriptorium-acp-", "")
    defer: removeDir(directory)
    var request = requestFor(directory, "permission")
    request.accessPolicy = accessReadOnly
    let response = runAgent(request)
    check response.lastMessage == "no-tail"

  test "restricted writes require reported paths in the operation allowlist":
    let directory = createTempDir("scriptorium-acp-", "")
    defer: removeDir(directory)
    var request = requestFor(directory, "permission")
    request.accessPolicy = accessRestricted
    request.allowedWritePaths = @["allowed.txt"]
    check runAgent(request).lastMessage == "yes-tail"
    request.allowedWritePaths = @["elsewhere"]
    check runAgent(request).lastMessage == "no-tail"

  test "restricted paths cannot escape through a symlink":
    let directory = createTempDir("scriptorium-acp-paths-", "")
    defer: removeDir(directory)
    createDir(directory / "allowed")
    createDir(directory / "outside")
    createSymlink(directory / "outside", directory / "allowed" / "escape")
    check not pathAllowed("allowed/escape/new.txt", directory, @["allowed"])
    check pathAllowed("allowed/new.txt", directory, @["allowed"])
    check not pathAllowed("allowed/../outside/new.txt", directory, @["allowed"])

  test "disconnects settle pending handles as transport errors":
    let directory = createTempDir("scriptorium-acp-", "")
    defer: removeDir(directory)
    let response = runAgent(requestFor(directory, "disconnect"))
    check response.exitCode == 1
    check response.failureKind == failureTransport

  test "transient retry limits are owned by the shared runner":
    let directory = createTempDir("scriptorium-acp-retry-", "")
    defer: removeDir(directory)
    var request = requestFor(directory, "disconnect")
    request.maxAttempts = 2
    check runAgent(request).attemptCount == 2
    request.prompt = "error"
    let permanent = runAgent(request)
    check permanent.attemptCount == 1
    check permanent.failureKind == failureRpc

  test "RPC errors retain code and data":
    let directory = createTempDir("scriptorium-acp-", "")
    defer: removeDir(directory)
    let response = runAgent(requestFor(directory, "error"))
    check response.failureKind == failureRpc
    check response.errorCode == -32010
    check response.errorData["detail"].getStr() == "retained"

  test "inactivity cancels cooperatively and keeps the session reusable":
    let directory = createTempDir("scriptorium-acp-", "")
    defer: removeDir(directory)
    var request = requestFor(directory, "silent")
    request.noOutputTimeoutMs = 50
    let session = openConversation(request)
    defer: session.close()
    let cancelled = session.runTurn(request)
    check cancelled.failureKind == failureTimeout
    check cancelled.timeoutKind == "no-output"
    request.prompt = "after"
    check session.runTurn(request).lastMessage == "after-tail"

  test "stderr is diagnostic and cannot reset inactivity":
    let directory = createTempDir("scriptorium-acp-", "")
    defer: removeDir(directory)
    var request = requestFor(directory, "noise")
    request.noOutputTimeoutMs = 50
    let response = runAgent(request)
    check response.failureKind == failureTimeout
    check "diagnostic noise" in readFile(response.logFile.replace(".jsonl", ".stderr.log"))
    check "diagnostic noise" notin readFile(response.logFile)

  test "unknown payloads remain structured and available to callers":
    let directory = createTempDir("scriptorium-acp-", "")
    defer: removeDir(directory)
    var request = requestFor(directory, "unknown")
    var retained = false
    request.onEvent = proc(event: AgentStreamEvent) =
      ## Inspect a future update without text-based protocol inference.
      if event.kind == agentEventUnknown:
        retained = event.update.raw["future"].getBool()
    discard runAgent(request)
    check retained

  test "saved conversations cannot change access policy":
    let directory = createTempDir("scriptorium-acp-", "")
    defer: removeDir(directory)
    var request = requestFor(directory, "first")
    let response = runAgent(request)
    request.resumeSessionId = response.sessionId
    request.accessPolicy = accessReadOnly
    expect ValueError:
      discard runAgent(request)

  test "completed assignments retire saved conversations":
    let directory = createTempDir("scriptorium-acp-complete-", "")
    defer: removeDir(directory)
    let request = normalizeRequest(requestFor(directory, "completed"))
    discard runAgent(request)
    completeSessionsForWorktree(request.sessionRoot, directory)
    check readSessionRecord(request).completed

  test "retired backends have no execution fallback":
    var request = requestFor(getTempDir(), "unused")
    request.acpAgent = ""
    request.harness = harnessTypoi
    expect ValueError:
      discard normalizeRequest(request)

removeFile(fixture)
