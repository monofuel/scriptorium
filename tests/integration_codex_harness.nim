## Integration tests for running the real codex binary.

import
  std/[os, strformat, strutils, tempfiles, times, unittest],
  scriptorium/[harness_codex, mcp_server, orchestrator]

const
  DefaultIntegrationModel = "gpt-5.6-sol"
  CodexAuthPathEnv = "CODEX_AUTH_FILE"
  LiveMcpBasePort = 22100
  LiveMcpPortRange = 80

proc mcpPort(offset: int): int =
  ## Return a process-specific port within this test file's reserved range.
  result = LiveMcpBasePort + (getCurrentProcessId().int mod LiveMcpPortRange) + offset

proc integrationModel(): string =
  ## Return the configured integration model, or the default model.
  result = getEnv("SCRIPTORIUM_TEST_MODEL", "")
  if result.len == 0:
    result = getEnv("CODEX_INTEGRATION_MODEL", DefaultIntegrationModel)

proc codexAuthPath(): string =
  ## Return the configured Codex auth file path used for OAuth credentials.
  let overridePath = getEnv(CodexAuthPathEnv, "").strip()
  if overridePath.len > 0:
    result = overridePath
  else:
    result = expandTilde("~/.codex/auth.json")

proc hasCodexAuth(): bool =
  ## Return true when API keys or a Codex OAuth auth file are available.
  let hasApiKey = getEnv("OPENAI_API_KEY", "").len > 0 or getEnv("CODEX_API_KEY", "").len > 0
  result = hasApiKey or fileExists(codexAuthPath())

suite "integration codex harness":
  test "real codex exec one-shot smoke test":
    let harnessEnv = getEnv("SCRIPTORIUM_TEST_HARNESS", "").strip()
    if harnessEnv.len > 0 and harnessEnv != "codex":
      skip()
    else:
      let codexPath = findExe("codex")
      doAssert codexPath.len > 0, "codex binary is required for integration tests"
      doAssert hasCodexAuth(),
        "OPENAI_API_KEY/CODEX_API_KEY or a Codex OAuth auth file is required for integration tests (" &
        codexAuthPath() & ")"

      let tmpDir = createTempDir("scriptorium_integration_codex_", "", getTempDir())
      defer:
        removeDir(tmpDir)

      let worktreePath = tmpDir / "worktree"
      createDir(worktreePath)
      let request = CodexRunRequest(
        prompt: "Reply with exactly: ok",
        workingDir: worktreePath,
        model: integrationModel(),
        ticketId: "integration-smoke",
        skipGitRepoCheck: true,
        logRoot: tmpDir / "logs",
        hardTimeoutMs: 45_000,
        noOutputTimeoutMs: 15_000,
      )

      let runResult = runCodex(request)
      doAssert runResult.exitCode == 0,
        "codex exec failed with non-zero exit code.\n" &
        "Model: " & integrationModel() & "\n" &
        "Command: " & runResult.command.join(" ") & "\n" &
        "Stdout:\n" & runResult.stdout
      doAssert runResult.lastMessage.strip().len > 0,
        "codex did not produce a last message.\n" &
        "Last message file: " & runResult.lastMessageFile & "\n" &
        "Stdout:\n" & runResult.stdout
      check fileExists(runResult.logFile)
      check fileExists(runResult.lastMessageFile)

  test "real codex MCP tool call against live server":
    let harnessEnv = getEnv("SCRIPTORIUM_TEST_HARNESS", "").strip()
    if harnessEnv.len > 0 and harnessEnv != "codex":
      skip()
    else:
      let codexPath = findExe("codex")
      doAssert codexPath.len > 0, "codex binary is required for integration tests"
      doAssert hasCodexAuth(),
        "OPENAI_API_KEY/CODEX_API_KEY or a Codex OAuth auth file is required for integration tests (" &
        codexAuthPath() & ")"

      let port = mcpPort(1)
      let endpoint = &"http://127.0.0.1:{port}"

      let httpServer = createAgentMcpHost()
      var serverThread: Thread[ServerThreadArgs]
      createThread(serverThread, runHttpServer, (httpServer, "127.0.0.1", port))
      waitForServerReady("127.0.0.1", port)

      let tmpDir = createTempDir("scriptorium_integration_codex_mcp_", "", getTempDir())
      defer:
        removeDir(tmpDir)

      let
        worktreePath = tmpDir / "worktree"
        timestamp = now().utc().format("yyyyMMddHHmmss")
        nonce = &"it-codex-mcp-{getCurrentProcessId()}-{timestamp}"
      createDir(worktreePath)
      let mcpSession = newCodingMcpSession(endpoint, "integration-codex-mcp", "integration", worktreePath)
      defer: unregisterAgentMcpSession(mcpSession)

      let prompt =
        "You are running an integration test. " &
        "You have a function called submit_pr in your tool list. " &
        "Use the submit_pr function exactly once with the argument summary=\"" & nonce & "\". " &
        "Do not execute any shell commands. Do not search the filesystem. " &
        "After the function call succeeds, reply with exactly DONE."

      let request = CodexRunRequest(
        prompt: prompt,
        workingDir: worktreePath,
        model: integrationModel(),
        mcpEndpoint: mcpSession.endpoint,
        ticketId: "integration-codex-mcp",
        skipGitRepoCheck: true,
        logRoot: tmpDir / "logs",
        hardTimeoutMs: 120_000,
        noOutputTimeoutMs: 45_000,
      )

      let runResult = runCodex(request)
      doAssert runResult.exitCode == 0,
        "codex MCP tool call failed.\n" &
        "Command: " & runResult.command.join(" ") & "\n" &
        "Stdout:\n" & runResult.stdout
      let consumedSummary = codingSubmission(mcpSession).summary
      doAssert consumedSummary == nonce,
        "expected submit_pr summary not captured.\n" &
        "Expected: " & nonce & "\n" &
        "Actual: " & consumedSummary & "\n" &
        "MCP requests: " & mcpRequestMethods(mcpSession).join(", ") & "\n" &
        "Stdout:\n" & runResult.stdout
      let requestMethods = mcpRequestMethods(mcpSession)
      check "initialize" in requestMethods
      check "tools/list" in requestMethods
      check "tools/call" in requestMethods
