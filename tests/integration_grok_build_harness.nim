## Integration tests for running the real grok ACP agent binary.

import
  std/[os, sequtils, strformat, strutils, tempfiles, times, unittest],
  mcport,
  scriptorium/[config, harness_grok_build, mcp_server, orchestrator]

const
  DefaultIntegrationModel = "grok-4.5"
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

proc hasGrokAuth(): bool =
  ## Return true when Grok auth is available via API key or cached login.
  let hasApiKey = getEnv("XAI_API_KEY", "").len > 0
  let hasOauth = fileExists(expandTilde("~/.grok/auth.json"))
  result = hasApiKey or hasOauth

suite "integration grok-build harness":
  test "real grok-build ACP one-shot smoke test":
    let harnessEnv = getEnv("SCRIPTORIUM_TEST_HARNESS", "").strip()
    if harnessEnv.len > 0 and harnessEnv != "grok-build":
      skip()
    else:
      let grokPath = findExe("grok")
      doAssert grokPath.len > 0, "grok binary is required for integration tests"
      doAssert hasGrokAuth(),
        "Grok auth is required (XAI_API_KEY or ~/.grok/auth.json)"

      let tmpDir = createTempDir("scriptorium_integration_grok_build_", "", getTempDir())
      defer:
        removeDir(tmpDir)

      let worktreePath = tmpDir / "worktree"
      createDir(worktreePath)
      var events: seq[string] = @[]
      var request = GrokBuildRunRequest(
        prompt: "Reply with exactly: ok. No tools.",
        workingDir: worktreePath,
        model: integrationModel(),
        ticketId: "integration-smoke",
        logRoot: tmpDir / "logs",
        hardTimeoutMs: 120_000,
        noOutputTimeoutMs: 60_000,
      )
      request.onEvent = proc(event: GrokBuildStreamEvent) =
        ## Capture events for assertion.
        events.add($event.kind & ":" & event.text)

      let runResult = runGrokBuild(request)
      doAssert runResult.exitCode == 0,
        "grok-build failed with non-zero exit code.\n" &
        "Model: " & integrationModel() & "\n" &
        "Command: " & runResult.command.join(" ") & "\n" &
        "Stdout:\n" & runResult.stdout
      doAssert runResult.lastMessage.strip().len > 0,
        "grok-build did not produce a last message.\n" &
        "Last message file: " & runResult.lastMessageFile & "\n" &
        "Stdout:\n" & runResult.stdout
      check fileExists(runResult.logFile)
      check fileExists(runResult.lastMessageFile)
      check events.len > 0
      check events.anyIt("message" in it)
      check "ok" in runResult.lastMessage.toLowerAscii()

  test "real grok-build MCP tool call against live server":
    let harnessEnv = getEnv("SCRIPTORIUM_TEST_HARNESS", "").strip()
    if harnessEnv.len > 0 and harnessEnv != "grok-build":
      skip()
    else:
      let grokPath = findExe("grok")
      doAssert grokPath.len > 0, "grok binary is required for integration tests"
      doAssert hasGrokAuth(),
        "Grok auth is required (XAI_API_KEY or ~/.grok/auth.json)"

      discard consumeSubmitPrSummary()
      let port = mcpPort(1)
      let endpoint = &"http://127.0.0.1:{port}"

      let httpServer = createOrchestratorServer()
      var serverThread: Thread[ServerThreadArgs]
      createThread(serverThread, runHttpServer, (httpServer, "127.0.0.1", port))
      waitForServerReady("127.0.0.1", port)

      let tmpDir = createTempDir("scriptorium_integration_grok_build_mcp_", "", getTempDir())
      defer:
        removeDir(tmpDir)

      let
        worktreePath = tmpDir / "worktree"
        timestamp = now().utc().format("yyyyMMddHHmmss")
        nonce = &"it-grok-mcp-{getCurrentProcessId()}-{timestamp}"
      createDir(worktreePath)

      let prompt =
        "You are running an integration test.\n" &
        "Use MCP tools to call submit_pr exactly once.\n" &
        "The tool may appear as scriptorium__submit_pr via search_tool/use_tool.\n" &
        "Call it with summary=\"" & nonce & "\".\n" &
        "Do not run shell commands. Do not edit files.\n" &
        "After the tool call succeeds, reply with exactly DONE."

      let request = GrokBuildRunRequest(
        prompt: prompt,
        workingDir: worktreePath,
        model: integrationModel(),
        mcpEndpoint: endpoint,
        ticketId: "integration-mcp",
        logRoot: tmpDir / "logs",
        hardTimeoutMs: 180_000,
        noOutputTimeoutMs: 90_000,
      )

      let runResult = runGrokBuild(request)
      doAssert runResult.exitCode == 0,
        "grok-build MCP run failed.\n" &
        "Command: " & runResult.command.join(" ") & "\n" &
        "Stdout:\n" & runResult.stdout
      let summary = consumeSubmitPrSummary()
      doAssert summary == nonce,
        "submit_pr was not recorded with the expected summary.\n" &
        "Got: " & summary & "\n" &
        "Stdout:\n" & runResult.stdout
