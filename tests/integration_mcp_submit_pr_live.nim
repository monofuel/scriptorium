## Integration tests for live MCP submit_pr transport and real Codex tool calling.

import
  std/[httpclient, json, os, strformat, strutils, tempfiles, times, unittest],
  scriptorium/[agent_runner, config, harness_codex, orchestrator]

const
  LiveMcpBasePort = 22000
  LiveMcpPortRange = 80
  DefaultIntegrationModel = "gpt-5.6-sol"
  CodexAuthPathEnv = "CODEX_AUTH_FILE"
  RpcTimeoutMs = 30_000
  CodexHardTimeoutMs = 120_000
  CodexNoOutputTimeoutMs = 45_000
  ClientProtocolVersion = "2025-06-18"

var
  liveMcpHost: AgentMcpHost
  liveMcpThread: Thread[ServerThreadArgs]

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

proc integrationHarness(): Harness =
  ## Return the test harness from env, or infer from model.
  let envVal = getEnv("SCRIPTORIUM_TEST_HARNESS", "").strip().toLowerAscii()
  if envVal.len > 0:
    case envVal
    of "codex": result = harnessCodex
    of "claude-code": result = harnessClaudeCode
    of "typoi": result = harnessTypoi
    of "grok-build": result = harnessGrokBuild
    else:
      raise newException(ValueError, "unknown SCRIPTORIUM_TEST_HARNESS: " & envVal)
  else:
    result = inferHarness(integrationModel())

proc hasAgentAuth(): bool =
  ## Return true when API keys are available for the configured test harness.
  let h = integrationHarness()
  case h
  of harnessCodex:
    result = hasCodexAuth()
  of harnessClaudeCode:
    let hasApiKey = getEnv("ANTHROPIC_API_KEY", "").len > 0
    let hasOauth = fileExists(expandTilde("~/.claude/.credentials.json"))
    result = hasApiKey or hasOauth
  of harnessTypoi:
    result = true
  of harnessGrokBuild:
    let hasApiKey = getEnv("XAI_API_KEY", "").len > 0
    let hasOauth = fileExists(expandTilde("~/.grok/auth.json"))
    result = hasApiKey or hasOauth

proc requiredAgentBinary(): string =
  ## Return the binary name needed for the configured test harness.
  let h = integrationHarness()
  case h
  of harnessCodex: result = "codex"
  of harnessClaudeCode: result = "claude"
  of harnessTypoi: result = "typoi"
  of harnessGrokBuild: result = "grok"

proc mcpPort(offset: int): int =
  ## Return a deterministic local MCP port for one test offset.
  result = LiveMcpBasePort + (getCurrentProcessId().int mod LiveMcpPortRange) + offset

proc mcpBaseUrl(port: int): string =
  ## Return the base MCP HTTP URL for one local port.
  result = &"http://127.0.0.1:{port}"

proc sharedMcpEndpoint(): string =
  ## Start and return the single MCP transport host shared by all tests in this process.
  let port = mcpPort(1)
  if liveMcpHost.isNil:
    liveMcpHost = createAgentMcpHost()
    createThread(liveMcpThread, runHttpServer, (liveMcpHost, "127.0.0.1", port))
    waitForServerReady("127.0.0.1", port)
  result = mcpBaseUrl(port)

proc mcpRequest(mcpUrl: string, requestId: int, methodName: string, params: JsonNode): JsonNode =
  ## Send one MCP JSON-RPC request over HTTP and return parsed JSON response.
  let payload = %*{
    "jsonrpc": "2.0",
    "id": requestId,
    "method": methodName,
    "params": params,
  }
  var client = newHttpClient(timeout = RpcTimeoutMs)
  defer:
    client.close()

  client.headers = newHttpHeaders({
    "Content-Type": "application/json",
  })
  let response = client.request(mcpUrl, httpMethod = HttpPost, body = $payload)
  let responseBody = response.body
  doAssert response.code == Http200, &"MCP HTTP request failed ({response.code}): {responseBody}"
  result = parseJson(responseBody)

proc initializeMcpSession(mcpUrl: string) =
  ## Perform one MCP initialize request to establish a client session.
  discard mcpRequest(
    mcpUrl,
    1,
    "initialize",
    %*{
      "protocolVersion": ClientProtocolVersion,
      "capabilities": {},
      "clientInfo": {
        "name": "scriptorium-integration-tests",
        "version": "1.0.0",
      },
    },
  )

suite "integration mcp submit_pr live":
  test "IT-LIVE-01 real MCP HTTP tools/list and tools/call for submit_pr":
    let endpoint = sharedMcpEndpoint()
    let mcpSession = newCodingMcpSession(endpoint, "0022", "ticket-0022", "/tmp/scriptorium-live-mcp")
    defer: unregisterAgentMcpSession(mcpSession)
    let mcpUrl = mcpSession.endpoint & "/mcp"

    initializeMcpSession(mcpUrl)

    let listResponse = mcpRequest(mcpUrl, 2, "tools/list", %*{})
    let tools = listResponse["result"]["tools"]
    check tools.len == 1
    check tools[0]["name"].getStr() == "submit_pr"
    check not tools[0]["inputSchema"]["properties"].hasKey("ticket_id")

    let summary = "integration-live-mcp-http"
    let callResponse = mcpRequest(
      mcpUrl,
      3,
      "tools/call",
      %*{
        "name": "submit_pr",
        "arguments": {
          "summary": summary,
        },
      },
    )
    let responseText = callResponse["result"]["content"][0]["text"].getStr()
    check responseText == "Merge request recorded."
    check codingSubmission(mcpSession).summary == summary

  test "IT-LIVE-02 real agent calls submit_pr against live MCP HTTP server":
    let agentBinary = requiredAgentBinary()
    doAssert findExe(agentBinary).len > 0,
      agentBinary & " binary is required for live integration tests"
    doAssert hasAgentAuth(),
      "API credentials are required for live integration tests"

    let endpoint = sharedMcpEndpoint()

    let tmpDir = createTempDir("scriptorium_integration_live_mcp_agent_", "", getTempDir())
    defer:
      removeDir(tmpDir)

    let
      worktreePath = tmpDir / "worktree"
      timestamp = now().utc().format("yyyyMMddHHmmss")
      nonce = &"it-live-02-{getCurrentProcessId()}-{timestamp}"
      harness = integrationHarness()
      prompt =
        "You are running an integration test. " &
        "You have a function called submit_pr in your tool list. " &
        "Use the submit_pr function exactly once with the argument summary=\"" & nonce & "\". " &
        "Do not execute any shell commands. Do not search the filesystem. " &
        "After the function call succeeds, reply with exactly DONE."
    createDir(worktreePath)
    let mcpSession = newCodingMcpSession(endpoint, "0022", "ticket-0022", worktreePath)
    defer: unregisterAgentMcpSession(mcpSession)

    let request = AgentRunRequest(
      prompt: prompt,
      workingDir: worktreePath,
      harness: harness,
      model: integrationModel(),
      mcpEndpoint: mcpSession.endpoint,
      ticketId: "integration-live-submit-pr",
      attempt: 1,
      skipGitRepoCheck: true,
      logRoot: tmpDir / "logs",
      hardTimeoutMs: CodexHardTimeoutMs,
      noOutputTimeoutMs: CodexNoOutputTimeoutMs,
      maxAttempts: 1,
    )

    let runResult = runAgent(request)
    doAssert runResult.exitCode == 0,
      "agent failed to complete live MCP submit_pr integration.\n" &
      "Command: " & runResult.command.join(" ") & "\n" &
      "Stdout:\n" & runResult.stdout
    let consumedSummary = codingSubmission(mcpSession).summary
    doAssert consumedSummary == nonce,
      "expected live submit_pr summary was not captured.\n" &
      "Expected: " & nonce & "\n" &
      "Actual: " & consumedSummary & "\n" &
      "MCP requests: " & mcpRequestMethods(mcpSession).join(", ") & "\n" &
      "Stdout:\n" & runResult.stdout
    let requestMethods = mcpRequestMethods(mcpSession)
    check "initialize" in requestMethods
    check "tools/list" in requestMethods
    check "tools/call" in requestMethods

  test "IT-LIVE-03 codex-specific: mcp list confirms server is enabled and required":
    let harnessEnv3 = getEnv("SCRIPTORIUM_TEST_HARNESS", "").strip()
    if harnessEnv3.len > 0 and harnessEnv3 != "codex":
      skip()
    else:
      let codexPath = findExe("codex")
      doAssert codexPath.len > 0, "codex binary is required for live integration tests"

      let endpoint = sharedMcpEndpoint()
      let mcpSession = newCodingMcpSession(endpoint, "mcp-list", "mcp-list", getTempDir())
      defer: unregisterAgentMcpSession(mcpSession)

      let request = CodexRunRequest(
        mcpEndpoint: mcpSession.endpoint,
      )
      let (output, exitCode) = runCodexMcpList(codexPath, request)

      doAssert exitCode == 0,
        "codex mcp list --json failed.\n" &
        "Output:\n" & output

      let jsonOutput = parseJson(output.strip())
      doAssert jsonOutput.kind == JArray,
        "expected codex mcp list output to be a JSON array.\n" &
        "Output:\n" & output

      var foundScriptorium = false
      var isEnabled = false
      var isRequired = false
      var hasRequired = false

      for server in jsonOutput:
        if server["name"].getStr() == "scriptorium":
          foundScriptorium = true
          isEnabled = server["enabled"].getBool()
          if server.hasKey("required"):
            hasRequired = true
            isRequired = server["required"].getBool()

      check foundScriptorium
      check isEnabled
      if hasRequired:
        check isRequired
