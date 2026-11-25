import
  std/[httpclient, json, os, strformat, strutils, tempfiles, unittest],
  scriptorium/mcp_server

const
  ClientCount = 4
  RequestRounds = 40
  ChurnRounds = 300
  ClientTimeoutMs = 3000

type
  ClientArgs = tuple[url: string, role: AgentMcpRole]
  ClientResult = object
    error: string

var results: Channel[ClientResult]

proc sendRpc(client: HttpClient, url, body: string): JsonNode =
  ## Execute one finite real HTTP request and retain structured protocol errors.
  let response = client.request(url, httpMethod = HttpPost, body = body)
  doAssert response.code == Http200, $response.code & ": " & response.body
  parseJson(response.body)

proc clientWorker(args: ClientArgs) {.thread.} =
  ## Exercise one isolated role concurrently with other HTTP clients and registry churn.
  var outcome: ClientResult
  try:
    let client = newHttpClient(timeout = ClientTimeoutMs)
    defer: client.close()
    client.headers = newHttpHeaders({"Content-Type": "application/json; charset=utf-8"})
    discard sendRpc(client, args.url, $(%*{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
      "protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "finite-fixture", "version": "1"}}}))
    doAssert sendRpc(client, args.url, "{")["error"]["code"].getInt() == -32700
    doAssert sendRpc(client, args.url, "[]")["error"]["code"].getInt() == -32600
    let wrongTool = sendRpc(client, args.url, $(%*{"jsonrpc": "2.0", "id": 4, "method": "tools/call",
      "params": {"name": "not_a_scoped_tool", "arguments": {}}}))
    doAssert wrongTool.hasKey("error"), $wrongTool
    for round in 0..<RequestRounds:
      let listed = sendRpc(client, args.url, $(%*{"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}))
      doAssert listed["result"]["tools"].len == 1
      let name = listed["result"]["tools"][0]["name"].getStr()
      let arguments = case args.role
        of amrCoding: %*{"summary": "Finite UTF-8 ✓ " & repeat("x", 4000)}
        of amrManager: %*{"tickets": ["# Synthetic café ticket\n\n**Area:** synthetic"]}
        of amrReviewer: %*{"action": "request_changes", "feedback": "Synthetic refusal ✓"}
        of amrAudit: %*{"report": "Synthetic report ✓"}
        else: raise newException(ValueError, "Unexpected fixture role")
      let reply = sendRpc(client, args.url, $(%*{"jsonrpc": "2.0", "id": 3, "method": "tools/call",
        "params": {"name": name, "arguments": arguments}}))
      doAssert not reply.hasKey("error"), $reply
      GC_fullCollect()
  except CatchableError as error:
    outcome.error = error.msg
  results.send(outcome)

proc main() =
  ## Bound a real MCP HTTP ownership/collection stress fixture with explicit server and client teardown.
  let directory = createTempDir("scriptorium-mcp-concurrency-", "")
  defer: removeDir(directory)
  results.open()
  defer: results.close()
  let port = 28000 + getCurrentProcessId() mod 1000
  let endpoint = &"http://127.0.0.1:{port}"
  let host = createAgentMcpHost()
  var server: Thread[ServerThreadArgs]
  createThread(server, runHttpServer, (host, "127.0.0.1", port))
  defer:
    signalServerShutdown()
    joinThread(server)
  waitForServerReady("127.0.0.1", port)
  let sessions = @[
    newCodingMcpSession(endpoint, "0091", "ticket-0091", directory / "coding"),
    newManagerMcpSession(endpoint, "synthetic"),
    newReviewerMcpSession(endpoint, "0092"),
    newAuditMcpSession(endpoint)]
  defer:
    for session in sessions: unregisterAgentMcpSession(session)
  for session in sessions:
    session.server.initialized = false
  var clients: array[ClientCount, Thread[ClientArgs]]
  for index in 0..<ClientCount:
    createThread(clients[index], clientWorker, (sessions[index].endpoint & "/mcp", sessions[index].role))
  defer:
    for thread in clients.mitems: joinThread(thread)
  for index in 0..<ChurnRounds:
    let temporary = newReviewerMcpSession(endpoint, &"churn-{index}")
    unregisterAgentMcpSession(temporary)
    discard reviewerSubmission(sessions[2])
    GC_fullCollect()
    sleep(1)
  for index in 0..<ClientCount:
    let outcome = results.recv()
    doAssert outcome.error.len == 0, outcome.error
  for session in sessions:
    doAssert not session.server.initialized, "HTTP worker mutated the caller-owned MCP server graph"
  doAssert codingSubmission(sessions[0]).called
  doAssert managerSubmission(sessions[1]).tickets.len == 1
  doAssert reviewerSubmission(sessions[2]).action == "request_changes"
  doAssert auditSubmission(sessions[3]).report == "Synthetic report ✓"
  let expiredUrl = sessions[2].endpoint & "/mcp"
  unregisterAgentMcpSession(sessions[2])
  doAssert reviewerSubmission(sessions[2]).action == "request_changes"
  let replacement = newReviewerMcpSession(endpoint, "different-ticket")
  defer: unregisterAgentMcpSession(replacement)
  let client = newHttpClient(timeout = ClientTimeoutMs)
  defer: client.close()
  client.headers = newHttpHeaders({"Content-Type": "application/json"})
  doAssert client.request(expiredUrl, httpMethod = HttpPost, body = "{}").code == Http404
  doAssert not reviewerSubmission(replacement).called
  echo "PASS concurrent real HTTP parse/tools/completion/registry churn and forced collection"

main()
