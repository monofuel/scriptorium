import
  std/[httpclient, json, os, osproc, strtabs, strutils, tables, tempfiles, unittest],
  scriptorium/[agent_runner, config, mcp_server]

const
  SwitchyardBaseUrl = "https://switchyard.mle.monofuel.dev/v1"
  SwitchyardModel = "auto-kev"
  DiscoveryTimeoutMs = 15_000
  HomeSetupTimeoutMs = 600_000
  AgentIdleTimeoutMs = 1_800_000
  AgentHardTimeoutMs = 2_400_000
  GatewayStopTimeoutMs = 30_000

proc requireSwitchyard() =
  ## Check the real route before starting Hermes or spending inference tokens.
  let client = newHttpClient(timeout = DiscoveryTimeoutMs,
    headers = newHttpHeaders({"Authorization": "Bearer unused"}))
  defer: client.close()
  let response = client.get(SwitchyardBaseUrl & "/models")
  if response.code != Http200:
    raise newException(IOError, "Switchyard /v1/models returned " & $response.code &
      "; restore " & SwitchyardBaseUrl & " before running the Hermes integration test")
  let catalog = parseJson(response.body)
  for model in catalog["data"]:
    if model["id"].getStr() == SwitchyardModel: return
  raise newException(ValueError, "Switchyard did not advertise auto-kev")

proc runHermesCommand(binary, home: string, args: seq[string], timeoutMs: int) =
  ## Run a bounded native command against the temporary Hermes home.
  let environment = newStringTable(modeCaseSensitive)
  for key, value in envPairs(): environment[key] = value
  environment["HERMES_HOME"] = home
  let process = startProcess(binary, args = args,
    env = environment, options = {poParentStreams})
  defer: process.close()
  let code = process.waitForExit(timeoutMs)
  if code == -1:
    process.kill()
    discard process.waitForExit()
    raise newException(IOError, "Hermes " & args.join(" ") & " timed out")
  if code != 0:
    raise newException(IOError, "Hermes " & args.join(" ") & " failed: " & $code)

suite "system Hermes ACP integration":
  test "real file tools and scoped submit_pr work through Scriptorium":
    let binary = findExe("hermes")
    doAssert binary.len > 0, "Install system Hermes with ACP dependencies first"
    requireSwitchyard()
    let
      directory = createTempDir("scriptorium-hermes-integration-", "")
      workspace = directory / "workspace"
      home = directory / "hermes-home"
      nonce = "hermes-acp-" & $getCurrentProcessId()
      artifactRoot = absolutePath(".build/live/hermes")
    createDir(workspace)
    createDir(home)
    defer: removeDir(directory)
    writeFile(home / "config.yaml", """model:
  provider: custom
  base_url: https://switchyard.mle.monofuel.dev/v1
  api_key: unused
  default: auto-kev
  context_length: 1048576
providers:
  custom:
    request_timeout_seconds: 1200
    stale_timeout_seconds: 1200
auxiliary:
  background_review:
    enabled: false
curator:
  enabled: false
terminal:
  backend: local
""")
    runHermesCommand(binary, home, @["acp", "--check"], HomeSetupTimeoutMs)
    let
      port = 35000 + (getCurrentProcessId() mod 1000)
      endpoint = "http://127.0.0.1:" & $port
      host = createAgentMcpHost()
    var serverThread: Thread[ServerThreadArgs]
    createThread(serverThread, runHttpServer, (host, "127.0.0.1", port))
    waitForServerReady("127.0.0.1", port)
    defer:
      signalServerShutdown()
      joinThread(serverThread)
    let mcp = newCodingMcpSession(endpoint, "hermes-integration", "test-branch", workspace)
    defer: unregisterAgentMcpSession(mcp)
    var environment = {"HERMES_HOME": home}.toTable()
    if fileExists("/etc/ssl/certs/ca-certificates.crt"):
      environment["SSL_CERT_FILE"] = getEnv("SSL_CERT_FILE", "/etc/ssl/certs/ca-certificates.crt")
    var messages, tools: int
    let onEvent = proc(event: AgentStreamEvent) =
      ## Observe standard ACP updates without inspecting private CLI output.
      if event.kind == agentEventMessage: inc messages
      if event.kind == agentEventTool: inc tools
    let request = AgentRunRequest(
      prompt: "Write proof.txt in the working directory containing exactly " & nonce &
        ". Then call the scriptorium submit_pr MCP tool with summary " & nonce &
        ". Use real tools, do not delegate, then reply DONE and stop.",
      workingDir: workspace, acpAgent: "hermes",
      profile: AcpAgentProfile(command: binary, args: @["acp"], env: environment),
      mcpEndpoint: mcp.endpoint, ticketId: nonce, logRoot: artifactRoot,
      sessionRoot: directory / "sessions", noOutputTimeoutMs: AgentIdleTimeoutMs,
      hardTimeoutMs: AgentHardTimeoutMs, onEvent: onEvent,
    )
    defer: runHermesCommand(binary, home, @["gateway", "stop", "--interrupt"], GatewayStopTimeoutMs)
    let response = runAgent(request)
    response.requireAgentCompleted()
    check response.sessionId.len > 0
    check messages > 0
    check tools > 0
    check readFile(workspace / "proof.txt").strip() == nonce
    check codingSubmission(mcp) == (called: true, summary: nonce)
    check "tools/call" in mcpRequestMethods(mcp)
