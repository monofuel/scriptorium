## Integration tests for running the real Claude Code binary.

import
  std/[os, sequtils, strformat, strutils, tempfiles, times, unittest],
  mcport,
  scriptorium/[harness_claude_code, orchestrator]

const
  DefaultIntegrationModel = "claude-sonnet-4-6"
  LiveMcpBasePort = 22200
  ServerStartupSleepMs = 250

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

proc hasClaudeAuth(): bool =
  ## Return true when Claude Code OAuth or an Anthropic API key is available.
  let hasApiKey = getEnv("ANTHROPIC_API_KEY", "").len > 0
  let hasOauth = fileExists(expandTilde("~/.claude/.credentials.json"))
  result = hasApiKey or hasOauth

suite "integration claude-code harness":
  test "real claude-code one-shot smoke test":
    let harnessEnv = getEnv("SCRIPTORIUM_TEST_HARNESS", "").strip()
    if harnessEnv.len > 0 and harnessEnv != "claude-code":
      skip()
    else:
      let claudePath = findExe("claude")
      doAssert claudePath.len > 0, "claude binary is required for integration tests"
      doAssert hasClaudeAuth(),
        "Claude Code auth is required (ANTHROPIC_API_KEY or ~/.claude/.credentials.json)"

      let tmpDir = createTempDir("scriptorium_integration_claude_code_", "", getTempDir())
      defer:
        removeDir(tmpDir)

      let worktreePath = tmpDir / "worktree"
      createDir(worktreePath)
      let request = ClaudeCodeRunRequest(
        prompt: "Reply with exactly: ok",
        workingDir: worktreePath,
        model: integrationModel(),
        ticketId: "integration-smoke",
        logRoot: tmpDir / "logs",
        hardTimeoutMs: 60_000,
        noOutputTimeoutMs: 30_000,
      )

      var events: seq[string] = @[]
      var mutableRequest = request
      mutableRequest.onEvent = proc(event: ClaudeCodeStreamEvent) =
        ## Capture events for assertion.
        events.add($event.kind & ":" & event.text)

      let runResult = runClaudeCode(mutableRequest)
      doAssert runResult.exitCode == 0,
        "claude-code failed with non-zero exit code.\n" &
        "Model: " & integrationModel() & "\n" &
        "Command: " & runResult.command.join(" ") & "\n" &
        "Stdout:\n" & runResult.stdout
      doAssert runResult.lastMessage.strip().len > 0,
        "claude-code did not produce a last message.\n" &
        "Last message file: " & runResult.lastMessageFile & "\n" &
        "Stdout:\n" & runResult.stdout
      check fileExists(runResult.logFile)
      check fileExists(runResult.lastMessageFile)
      check events.len > 0
      check events.anyIt("status" in it and "init" in it)
      check events.anyIt("message" in it)

  test "real claude-code MCP tool call against live server":
    let harnessEnv = getEnv("SCRIPTORIUM_TEST_HARNESS", "").strip()
    if harnessEnv.len > 0 and harnessEnv != "claude-code":
      skip()
    else:
      let claudePath = findExe("claude")
      doAssert claudePath.len > 0, "claude binary is required for integration tests"
      doAssert hasClaudeAuth(),
        "Claude Code auth is required (ANTHROPIC_API_KEY or ~/.claude/.credentials.json)"

      discard consumeSubmitPrSummary()
      let port = mcpPort(1)
      let endpoint = &"http://127.0.0.1:{port}"

      let httpServer = createOrchestratorServer()
      var serverThread: Thread[ServerThreadArgs]
      createThread(serverThread, runHttpServer, (httpServer, "127.0.0.1", port))
      sleep(ServerStartupSleepMs)

      let tmpDir = createTempDir("scriptorium_integration_claude_code_mcp_", "", getTempDir())
      defer:
        removeDir(tmpDir)

      let
        worktreePath = tmpDir / "worktree"
        timestamp = now().utc().format("yyyyMMddHHmmss")
        nonce = &"it-claude-mcp-{getCurrentProcessId()}-{timestamp}"
      createDir(worktreePath)

      let prompt =
        "You are running an integration test. " &
        "You have a function called submit_pr in your tool list. " &
        "Use the submit_pr function exactly once with the argument summary=\"" & nonce & "\". " &
        "Do not execute any shell commands. Do not search the filesystem. " &
        "If the function is missing, fail immediately. " &
        "After the function call succeeds, reply with exactly DONE."

      let request = ClaudeCodeRunRequest(
        prompt: prompt,
        workingDir: worktreePath,
        model: integrationModel(),
        mcpEndpoint: endpoint,
        ticketId: "integration-claude-mcp",
        logRoot: tmpDir / "logs",
        hardTimeoutMs: 120_000,
        noOutputTimeoutMs: 45_000,
      )

      let runResult = runClaudeCode(request)
      doAssert runResult.exitCode == 0,
        "claude-code MCP tool call failed.\n" &
        "Command: " & runResult.command.join(" ") & "\n" &
        "Stdout:\n" & runResult.stdout
      let consumedSummary = consumeSubmitPrSummary()
      doAssert consumedSummary == nonce,
        "expected submit_pr summary not captured.\n" &
        "Expected: " & nonce & "\n" &
        "Actual: " & consumedSummary & "\n" &
        "Stdout:\n" & runResult.stdout
