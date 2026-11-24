import
  std/[httpclient, json, os, tempfiles, unittest],
  scriptorium/[git_ops, mcp_server]

proc rpc(endpoint, methodName: string, params: JsonNode): JsonNode =
  ## Call the actual scoped HTTP MCP transport without a model or fake server.
  let client = newHttpClient(timeout = 5000)
  defer: client.close()
  client.headers = newHttpHeaders({"Content-Type": "application/json"})
  let response = client.request(endpoint & "/mcp", httpMethod = HttpPost,
    body = $(%*{"jsonrpc": "2.0", "id": 1, "method": methodName, "params": params}))
  doAssert response.code == Http200, response.body
  parseJson(response.body)

suite "scoped project reads over real MCP HTTP":
  test "actual bytes, input errors, tool isolation, and capability expiry":
    let
      root = createTempDir("scriptorium-project-http-", "")
      project = root / "project"
      plan = root / "plan"
    defer: removeDir(root)
    createDir(project)
    createDir(plan)
    let initialized = runCommandCapture(project, "git", @["init", "-q"])
    doAssert initialized.exitCode == 0, initialized.output
    writeFile(project / "AGENTS.md", "Actual synthetic instructions.")
    gitRun(project, "add", "AGENTS.md")
    writeFile(plan / "spec.md", "Actual synthetic specification.")
    let
      port = 26000 + getCurrentProcessId() mod 1000
      endpoint = "http://127.0.0.1:" & $port
      host = createAgentMcpHost()
    var thread: Thread[ServerThreadArgs]
    createThread(thread, runHttpServer, (host, "127.0.0.1", port))
    defer:
      signalServerShutdown()
      joinThread(thread)
    waitForServerReady("127.0.0.1", port)
    let session = newProjectReadMcpSession(endpoint, project, plan)
    defer: unregisterAgentMcpSession(session)
    discard rpc(session.endpoint, "initialize", %*{
      "protocolVersion": "2025-06-18", "capabilities": {},
      "clientInfo": {"name": "project-read-http-test", "version": "1"}})
    let tools = rpc(session.endpoint, "tools/list", %*{})["result"]["tools"]
    check tools.len == 2
    let spec = rpc(session.endpoint, "tools/call", %*{"name": "get_spec", "arguments": {}})
    check spec["result"]["structuredContent"]["text"].getStr() == readFile(plan / "spec.md")
    check parseJson(spec["result"]["content"][0]["text"].getStr())["text"].getStr() == readFile(plan / "spec.md")
    let source = rpc(session.endpoint, "tools/call", %*{
      "name": "read_project_file", "arguments": {"path": "AGENTS.md"}})
    check source["result"]["structuredContent"]["text"].getStr() == readFile(project / "AGENTS.md")
    check parseJson(source["result"]["content"][0]["text"].getStr())["text"].getStr() == readFile(project / "AGENTS.md")
    let denied = rpc(session.endpoint, "tools/call", %*{
      "name": "read_project_file", "arguments": {"path": ".git/config"}})
    check denied.hasKey("error")
    let wrongTool = rpc(session.endpoint, "tools/call", %*{"name": "submit_pr", "arguments": {"summary": "no"}})
    check wrongTool.hasKey("error")
    unregisterAgentMcpSession(session)
    let client = newHttpClient(timeout = 5000)
    defer: client.close()
    check client.request(session.endpoint & "/mcp", httpMethod = HttpPost, body = "{}").code == Http404
