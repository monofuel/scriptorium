import
  std/[httpclient, json, os, unittest],
  scriptorium/mcp_server

proc rpc(endpoint, methodName: string, params: JsonNode): JsonNode =
  ## Send an actual JSON-RPC request through the scoped HTTP MCP transport.
  let client = newHttpClient(timeout = 5000)
  defer: client.close()
  client.headers = newHttpHeaders({"Content-Type": "application/json"})
  let response = client.request(endpoint & "/mcp", httpMethod = HttpPost,
    body = $(%*{"jsonrpc": "2.0", "id": 1, "method": methodName, "params": params}))
  doAssert response.code == Http200, response.body
  parseJson(response.body)

proc submit(endpoint: string, arguments: JsonNode) =
  ## Submit one review using the real server and its tool validation.
  discard rpc(endpoint, "tools/call", %*{"name": "submit_review", "arguments": arguments})

suite "review verdicts over scoped MCP HTTP":
  test "only a valid current-session verdict completes the assigned review":
    let
      port = 35000 + getCurrentProcessId() mod 1000
      endpoint = "http://127.0.0.1:" & $port
      host = createAgentMcpHost()
    var thread: Thread[ServerThreadArgs]
    createThread(thread, runHttpServer, (host, "127.0.0.1", port))
    defer:
      signalServerShutdown()
      joinThread(thread)
    waitForServerReady("127.0.0.1", port)

    let
      previous = newReviewerMcpSession(endpoint, "ticket")
      current = newReviewerMcpSession(endpoint, "ticket")
      other = newReviewerMcpSession(endpoint, "other-ticket")
    defer:
      unregisterAgentMcpSession(previous)
      unregisterAgentMcpSession(current)
      unregisterAgentMcpSession(other)
    for session in [previous, current, other]:
      discard rpc(session.endpoint, "initialize", %*{
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": "review-gate-test", "version": "1"}})

    submit(previous.endpoint, %*{"action": "approve"})
    submit(other.endpoint, %*{"action": "approve_with_warnings", "feedback": "Warning."})
    check reviewerSubmission(previous).action == "approve"
    check reviewerSubmission(other).action == "approve_with_warnings"
    check not reviewerSubmission(current).called
    unregisterAgentMcpSession(previous)
    let client = newHttpClient(timeout = 5000)
    defer: client.close()
    check client.request(previous.endpoint & "/mcp", httpMethod = HttpPost, body = "{}").code == Http404
    check not reviewerSubmission(current).called

    for arguments in [%*{}, %*{"action": "approved"}, %*{"action": true},
        %*{"action": "approve", "ticketId": "other-ticket"},
        %*{"action": "approve", "feedback": false},
        %*{"action": "request_changes", "feedback": "  "}]:
      submit(current.endpoint, arguments)
      check not reviewerSubmission(current).called
    submit(current.endpoint, %*{"action": "request_changes", "feedback": "Fix first."})
    submit(current.endpoint, %*{"action": "approve"})
    check reviewerSubmission(current) == (called: true, action: "request_changes", feedback: "Fix first.")
