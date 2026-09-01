## Integration tests for scoped MCP servers over the real HTTP transport.

import
  std/[httpclient, json, os, strformat, unittest],
  scriptorium/mcp_server

const
  BasePort = 25000
  PortRange = 80
  RpcTimeoutMs = 10_000

proc testPort(): int =
  ## Return a process-specific local integration test port.
  result = BasePort + (getCurrentProcessId().int mod PortRange)

proc rpcRequest(url: string, requestId: int, methodName: string, params: JsonNode): JsonNode =
  ## Send one JSON-RPC request to a scoped MCP endpoint.
  let payload = %*{
    "jsonrpc": "2.0",
    "id": requestId,
    "method": methodName,
    "params": params,
  }
  var client = newHttpClient(timeout = RpcTimeoutMs)
  defer: client.close()
  client.headers = newHttpHeaders({"Content-Type": "application/json"})
  let response = client.request(url, httpMethod = HttpPost, body = $payload)
  doAssert response.code == Http200, response.body
  result = parseJson(response.body)

suite "scoped MCP HTTP transport":
  test "routes each token to its exact server and expires it on unregister":
    let port = testPort()
    let endpoint = &"http://127.0.0.1:{port}"
    let host = createAgentMcpHost()
    var serverThread: Thread[ServerThreadArgs]
    createThread(serverThread, runHttpServer, (host, "127.0.0.1", port))
    waitForServerReady("127.0.0.1", port)

    let coding = newCodingMcpSession(endpoint, "0070", "ticket-0070", "/tmp/wt-0070")
    let manager = newManagerMcpSession(endpoint, "backend")
    defer: unregisterAgentMcpSession(manager)

    let codingUrl = coding.endpoint & "/mcp"
    let managerUrl = manager.endpoint & "/mcp"
    discard rpcRequest(codingUrl, 1, "initialize", %*{
      "protocolVersion": "2025-06-18",
      "capabilities": {},
      "clientInfo": {"name": "test", "version": "1"},
    })
    discard rpcRequest(managerUrl, 2, "initialize", %*{
      "protocolVersion": "2025-06-18",
      "capabilities": {},
      "clientInfo": {"name": "test", "version": "1"},
    })

    let codingTools = rpcRequest(codingUrl, 3, "tools/list", %*{})["result"]["tools"]
    let managerTools = rpcRequest(managerUrl, 4, "tools/list", %*{})["result"]["tools"]
    check codingTools.len == 1
    check codingTools[0]["name"].getStr() == "submit_pr"
    check managerTools.len == 1
    check managerTools[0]["name"].getStr() == "submit_tickets"

    discard rpcRequest(codingUrl, 5, "tools/call", %*{
      "name": "submit_pr",
      "arguments": {},
    })
    check codingSubmission(coding).called
    check not managerSubmission(manager).called

    unregisterAgentMcpSession(coding)
    var client = newHttpClient(timeout = RpcTimeoutMs)
    defer: client.close()
    client.headers = newHttpHeaders({"Content-Type": "application/json"})
    let expiredResponse = client.request(codingUrl, httpMethod = HttpPost, body = "{}")
    check expiredResponse.code == Http404

    let legacyResponse = client.request(endpoint & "/mcp", httpMethod = HttpPost, body = "{}")
    check legacyResponse.code == Http404
