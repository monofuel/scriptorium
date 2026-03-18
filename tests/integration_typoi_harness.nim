## Integration tests for running the real typoi binary.

import
  std/[os, sequtils, strformat, strutils, tempfiles, times, unittest],
  mcport,
  scriptorium/[harness_typoi, mcp_server, orchestrator]

const
  DefaultIntegrationModel = "claude-opus-4-6"
  LiveMcpBasePort = 22300

type
  ServerThreadArgs = tuple[
    httpServer: HttpMcpServer,
    address: string,
    port: int,
  ]

proc runHttpServer(args: ServerThreadArgs) {.thread.} =
  args.httpServer.serve(args.port, args.address)

proc mcpPort(offset: int): int =
  result = LiveMcpBasePort + (getCurrentProcessId().int mod 1000) + offset

proc integrationModel(): string =
  ## Return the configured integration model, or the default model.
  result = getEnv("SCRIPTORIUM_TEST_MODEL", DefaultIntegrationModel)

proc hasTypoiAuth(): bool =
  ## Return true when API keys are available for typoi.
  let hasOpenAiKey = getEnv("OPENAI_API_KEY", "").len > 0
  let hasAnthropicKey = getEnv("ANTHROPIC_API_KEY", "").len > 0
  result = hasOpenAiKey or hasAnthropicKey

suite "integration typoi harness":
  test "real typoi one-shot smoke test":
    let harnessEnv = getEnv("SCRIPTORIUM_TEST_HARNESS", "").strip()
    if harnessEnv.len > 0 and harnessEnv != "typoi":
      skip()
    else:
      let typoiPath = findExe("typoi")
      doAssert typoiPath.len > 0, "typoi binary is required for integration tests"
      doAssert hasTypoiAuth(),
        "API key is required (OPENAI_API_KEY or ANTHROPIC_API_KEY)"

      let tmpDir = createTempDir("scriptorium_integration_typoi_", "", getTempDir())
      defer:
        removeDir(tmpDir)

      let worktreePath = tmpDir / "worktree"
      createDir(worktreePath)
      let request = TypoiRunRequest(
        prompt: "Reply with exactly: ok",
        workingDir: worktreePath,
        model: integrationModel(),
        ticketId: "integration-smoke",
        logRoot: tmpDir / "logs",
        hardTimeoutMs: 45_000,
        noOutputTimeoutMs: 15_000,
      )

      var events: seq[string] = @[]
      var mutableRequest = request
      mutableRequest.onEvent = proc(event: TypoiStreamEvent) =
        ## Capture events for assertion.
        events.add($event.kind & ":" & event.text)

      let runResult = runTypoi(mutableRequest)
      doAssert runResult.exitCode == 0,
        "typoi failed with non-zero exit code.\n" &
        "Model: " & integrationModel() & "\n" &
        "Command: " & runResult.command.join(" ") & "\n" &
        "Stdout:\n" & runResult.stdout
      doAssert runResult.lastMessage.strip().len > 0,
        "typoi did not produce a last message.\n" &
        "Last message file: " & runResult.lastMessageFile & "\n" &
        "Stdout:\n" & runResult.stdout
      check fileExists(runResult.logFile)
      check fileExists(runResult.lastMessageFile)
      check events.len > 0
      check events.anyIt("message" in it)

  test "real typoi MCP tool call against live server":
    let harnessEnv = getEnv("SCRIPTORIUM_TEST_HARNESS", "").strip()
    if harnessEnv.len > 0 and harnessEnv != "typoi":
      skip()
    else:
      let typoiPath = findExe("typoi")
      doAssert typoiPath.len > 0, "typoi binary is required for integration tests"
      doAssert hasTypoiAuth(),
        "API key is required (OPENAI_API_KEY or ANTHROPIC_API_KEY)"

      discard consumeSubmitPrSummary()
      let port = mcpPort(1)
      let endpoint = &"http://127.0.0.1:{port}"

      let httpServer = createOrchestratorServer()
      var serverThread: Thread[ServerThreadArgs]
      createThread(serverThread, runHttpServer, (httpServer, "127.0.0.1", port))
      waitForServerReady("127.0.0.1", port)

      let tmpDir = createTempDir("scriptorium_integration_typoi_mcp_", "", getTempDir())
      defer:
        removeDir(tmpDir)

      let
        worktreePath = tmpDir / "worktree"
        timestamp = now().utc().format("yyyyMMddHHmmss")
        nonce = &"it-typoi-mcp-{getCurrentProcessId()}-{timestamp}"
      createDir(worktreePath)

      let prompt =
        "You are running an integration test. " &
        "You have a function called submit_pr in your tool list. " &
        "Use the submit_pr function exactly once with the argument summary=\"" & nonce & "\". " &
        "Do not execute any shell commands. Do not search the filesystem. " &
        "If the function is missing, fail immediately. " &
        "After the function call succeeds, reply with exactly DONE."

      let request = TypoiRunRequest(
        prompt: prompt,
        workingDir: worktreePath,
        model: integrationModel(),
        mcpEndpoint: endpoint,
        ticketId: "integration-typoi-mcp",
        logRoot: tmpDir / "logs",
        hardTimeoutMs: 120_000,
        noOutputTimeoutMs: 45_000,
      )

      let runResult = runTypoi(request)
      doAssert runResult.exitCode == 0,
        "typoi MCP tool call failed.\n" &
        "Command: " & runResult.command.join(" ") & "\n" &
        "Stdout:\n" & runResult.stdout
      let consumedSummary = consumeSubmitPrSummary()
      doAssert consumedSummary == nonce,
        "expected submit_pr summary not captured.\n" &
        "Expected: " & nonce & "\n" &
        "Actual: " & consumedSummary & "\n" &
        "Stdout:\n" & runResult.stdout
