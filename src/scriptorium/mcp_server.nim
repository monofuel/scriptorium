import
  std/[json, locks, os, strformat, strutils, tables, times],
  std/httpclient as std_httpclient,
  jsony,
  mcport,
  mummy,
  mummy/routers,
  webby/httpheaders,
  ./agent_sessions

const
  OrchestratorServerName = "scriptorium-orchestrator"
  OrchestratorServerVersion = "0.1.0"
  AgentMcpRoutePrefix = "/agents/"
  AgentMcpTokenBytes = 32
  ReviewFeedbackMaxBytes* = 4096
  ReviewTruncationMarker* = "... [truncated]"
  ServerReadyTimeoutMs* = 5000
  ServerReadyPollIntervalMs = 50
  BuildCommitHash* = block:
    let fromEnv = staticExec("echo $BUILD_COMMIT").strip()
    if fromEnv.len > 0: fromEnv
    else: staticExec("git rev-parse --short HEAD 2>/dev/null").strip()

type
  AgentMcpRole* = enum
    amrCoding = "coding"
    amrManager = "manager"
    amrReviewer = "reviewer"
    amrAudit = "audit"

  AgentMcpSession* = ref object
    token*: string
    endpoint*: string
    role*: AgentMcpRole
    server*: McpServer
    ticketId*: string
    branch*: string
    worktree*: string
    areaId*: string
    completionCalled: bool
    summary: string
    tickets: seq[string]
    reviewAction: string
    reviewFeedback: string
    auditReport: string
    requestMethods: seq[string]

  AgentMcpHost* = ref object
    httpServer*: mummy.Server

  ServerThreadArgs* = tuple[
    httpServer: AgentMcpHost,
    address: string,
    port: int,
  ]

var
  agentMcpLock: Lock
  agentMcpLockInitialized = false
  agentMcpSessions: Table[string, AgentMcpSession]
  shutdownLock: Lock
  shutdownCond: Cond
  shutdownLockInitialized = false
  shutdownRequested = false

proc ensureAgentMcpLockInitialized() {.gcsafe.} =
  ## Initialize the scoped MCP session registry lock once.
  if not agentMcpLockInitialized:
    initLock(agentMcpLock)
    agentMcpLockInitialized = true

proc ensureShutdownLockInitialized*() =
  ## Initialize the shutdown coordination lock and condition variable.
  if not shutdownLockInitialized:
    initLock(shutdownLock)
    initCond(shutdownCond)
    shutdownLockInitialized = true

proc signalServerShutdown*() =
  ## Signal the server shutdown monitor to close the HTTP server.
  acquire(shutdownLock)
  shutdownRequested = true
  broadcast(shutdownCond)
  release(shutdownLock)

proc normalizedEndpointBase(endpoint: string): string =
  ## Return one endpoint without trailing slashes.
  result = endpoint.strip()
  while result.endsWith("/"):
    result.setLen(result.len - 1)
  if result.len == 0:
    raise newException(ValueError, "MCP endpoint cannot be empty")

proc newAgentMcpToken(): string =
  ## Generate one cryptographically random MCP session token.
  var
    randomFile: File
    bytes: array[AgentMcpTokenBytes, byte]
  if not open(randomFile, "/dev/urandom", fmRead):
    raise newException(IOError, "failed to open the OS random device")
  defer: randomFile.close()
  let bytesRead = randomFile.readBuffer(addr bytes[0], bytes.len)
  if bytesRead != bytes.len:
    raise newException(IOError, "failed to generate agent MCP session token")
  for value in bytes:
    result.add(value.toHex(2).toLowerAscii())

proc registerAgentMcpSession(session: AgentMcpSession, endpoint: string) =
  ## Register one scoped MCP session and assign its private endpoint.
  ensureAgentMcpLockInitialized()
  let endpointBase = normalizedEndpointBase(endpoint)
  withLock agentMcpLock:
    var token = newAgentMcpToken()
    while agentMcpSessions.hasKey(token):
      token = newAgentMcpToken()
    session.token = token
    session.endpoint = endpointBase & AgentMcpRoutePrefix & token
    agentMcpSessions[token] = session

proc unregisterAgentMcpSession*(session: AgentMcpSession) =
  ## Remove one scoped MCP session so its endpoint can no longer be called.
  if session.isNil or session.token.len == 0:
    return
  ensureAgentMcpLockInitialized()
  withLock agentMcpLock:
    agentMcpSessions.del(session.token)

proc lookupAgentMcpSession(token: string): AgentMcpSession {.gcsafe.} =
  ## Return one registered MCP session without holding the registry lock.
  ensureAgentMcpLockInitialized()
  {.cast(gcsafe).}:
    withLock agentMcpLock:
      result = agentMcpSessions.getOrDefault(token)

proc recordCompletion(session: AgentMcpSession, update: proc() {.gcsafe.}): bool {.gcsafe.} =
  ## Record the first completion call for a session and ignore later duplicates.
  ensureAgentMcpLockInitialized()
  {.cast(gcsafe).}:
    withLock agentMcpLock:
      if session.completionCalled:
        return false
      update()
      session.completionCalled = true
      result = true

proc recordRequestMethod(session: AgentMcpSession, requestBody: string) {.gcsafe.} =
  ## Record one MCP request method for transport diagnostics.
  let requestNode = parseJson(requestBody)
  let methodName = requestNode.getOrDefault("method").getStr("")
  {.cast(gcsafe).}:
    withLock agentMcpLock:
      session.requestMethods.add(methodName)

proc codingReceiptPath(worktree: string): string =
  ## Locate the durable completion receipt inside managed ticket state.
  runtimeStateDirectory(worktree) / "submission.json"

proc acknowledgeCodingSubmission*(session: AgentMcpSession) =
  ## Mark a durable receipt consumed after its merge-queue transition commits.
  let content = $(%*{"ticketId": session.ticketId, "branch": session.branch,
    "summary": session.summary, "pending": false})
  atomicRuntimeWrite(codingReceiptPath(session.worktree), content)

proc newCodingMcpSession*(endpoint, ticketId, branch, worktree: string): AgentMcpSession =
  ## Create and register a coding-agent MCP server bound to one ticket.
  let session = AgentMcpSession(
    role: amrCoding,
    ticketId: ticketId,
    branch: branch,
    worktree: worktree,
    server: newMcpServer(OrchestratorServerName & "-coding", OrchestratorServerVersion),
  )
  let receiptPath = codingReceiptPath(worktree)
  if fileExists(receiptPath):
    let receipt = parseFile(receiptPath)
    if receipt["ticketId"].getStr() == ticketId and receipt["branch"].getStr() == branch and
        receipt["pending"].getBool():
      session.completionCalled = true
      session.summary = receipt["summary"].getStr()
  let tool = McpTool(
    name: "submit_pr",
    description: "Signal that the assigned ticket is complete and ready for review",
    inputSchema: %*{
      "type": "object",
      "properties": {
        "summary": {
          "type": "string",
          "description": "Short summary of the completed changes",
          "minLength": 1
        }
      },
      "required": ["summary"],
      "additionalProperties": false
    },
  )
  let handler: ToolHandler = proc(arguments: JsonNode): JsonNode {.gcsafe.} =
    if arguments.isNil or arguments.kind != JObject:
      raise newException(ValueError, "submit_pr requires an object with a nonempty summary")
    let summary = arguments.getOrDefault("summary").getStr().strip()
    if summary.len == 0:
      raise newException(ValueError, "submit_pr requires a nonempty summary; describe the completed changes")
    discard recordCompletion(session, proc() {.gcsafe.} =
      atomicRuntimeWrite(receiptPath, $(%*{"ticketId": ticketId, "branch": branch,
        "summary": summary, "pending": true}))
      session.summary = summary
    )
    %*"Merge request recorded."
  session.server.registerTool(tool, handler)
  registerAgentMcpSession(session, endpoint)
  result = session

proc newManagerMcpSession*(endpoint, areaId: string): AgentMcpSession =
  ## Create and register a manager MCP server bound to one area.
  let session = AgentMcpSession(
    role: amrManager,
    areaId: areaId,
    server: newMcpServer(OrchestratorServerName & "-manager", OrchestratorServerVersion),
  )
  let tool = McpTool(
    name: "submit_tickets",
    description: "Submit generated tickets for the assigned area",
    inputSchema: %*{
      "type": "object",
      "properties": {
        "tickets": {
          "type": "array",
          "items": {"type": "string"},
          "description": "Array of ticket markdown content strings"
        }
      },
      "required": ["tickets"],
      "additionalProperties": false
    },
  )
  let handler: ToolHandler = proc(arguments: JsonNode): JsonNode {.gcsafe.} =
    var tickets: seq[string]
    for item in arguments["tickets"]:
      tickets.add(item.getStr())
    discard recordCompletion(session, proc() {.gcsafe.} =
      session.tickets = tickets
    )
    %*"Tickets recorded."
  session.server.registerTool(tool, handler)
  registerAgentMcpSession(session, endpoint)
  result = session

proc newReviewerMcpSession*(endpoint, ticketId: string): AgentMcpSession =
  ## Create and register a reviewer MCP server bound to one merge-queue ticket.
  let session = AgentMcpSession(
    role: amrReviewer,
    ticketId: ticketId,
    server: newMcpServer(OrchestratorServerName & "-reviewer", OrchestratorServerVersion),
  )
  let tool = McpTool(
    name: "submit_review",
    description: "Submit a review decision for the assigned ticket",
    inputSchema: %*{
      "type": "object",
      "properties": {
        "action": {
          "type": "string",
          "enum": ["approve", "approve_with_warnings", "request_changes"],
          "description": "Review action to take"
        },
        "feedback": {
          "type": "string",
          "description": "Feedback for the review (required when requesting changes)"
        }
      },
      "required": ["action"],
      "additionalProperties": false
    },
  )
  let handler: ToolHandler = proc(arguments: JsonNode): JsonNode {.gcsafe.} =
    let action = arguments["action"].getStr()
    if action != "approve" and action != "approve_with_warnings" and action != "request_changes":
      return %*"Invalid action. Must be \"approve\", \"approve_with_warnings\", or \"request_changes\"."
    var feedback = if arguments.hasKey("feedback"): arguments["feedback"].getStr() else: ""
    if action == "request_changes" and feedback.len == 0:
      return %*"Feedback is required when action is \"request_changes\"."
    if feedback.len > ReviewFeedbackMaxBytes:
      let textLength = ReviewFeedbackMaxBytes - ReviewTruncationMarker.len
      feedback = feedback[0..<textLength] & ReviewTruncationMarker
    discard recordCompletion(session, proc() {.gcsafe.} =
      session.reviewAction = action
      session.reviewFeedback = feedback
    )
    %*"Review decision recorded."
  session.server.registerTool(tool, handler)
  registerAgentMcpSession(session, endpoint)
  result = session

proc newAuditMcpSession*(endpoint: string): AgentMcpSession =
  ## Create and register an audit MCP server bound to one audit invocation.
  let session = AgentMcpSession(
    role: amrAudit,
    server: newMcpServer(OrchestratorServerName & "-audit", OrchestratorServerVersion),
  )
  let tool = McpTool(
    name: "submit_audit_report",
    description: "Submit the audit report for this invocation",
    inputSchema: %*{
      "type": "object",
      "properties": {
        "report": {
          "type": "string",
          "description": "Full markdown audit report"
        }
      },
      "required": ["report"],
      "additionalProperties": false
    },
  )
  let handler: ToolHandler = proc(arguments: JsonNode): JsonNode {.gcsafe.} =
    let report = arguments["report"].getStr()
    discard recordCompletion(session, proc() {.gcsafe.} =
      session.auditReport = report
    )
    %*"Audit report recorded."
  session.server.registerTool(tool, handler)
  registerAgentMcpSession(session, endpoint)
  result = session

proc codingSubmission*(session: AgentMcpSession): tuple[called: bool, summary: string] =
  ## Return the coding completion state for one scoped session.
  ensureAgentMcpLockInitialized()
  withLock agentMcpLock:
    result = (called: session.completionCalled, summary: session.summary)

proc managerSubmission*(session: AgentMcpSession): tuple[called: bool, tickets: seq[string]] =
  ## Return the manager completion state for one scoped session.
  ensureAgentMcpLockInitialized()
  withLock agentMcpLock:
    result = (called: session.completionCalled, tickets: session.tickets)

proc reviewerSubmission*(session: AgentMcpSession): tuple[called: bool, action: string, feedback: string] =
  ## Return the reviewer completion state for one scoped session.
  ensureAgentMcpLockInitialized()
  withLock agentMcpLock:
    result = (
      called: session.completionCalled,
      action: session.reviewAction,
      feedback: session.reviewFeedback,
    )

proc auditSubmission*(session: AgentMcpSession): tuple[called: bool, report: string] =
  ## Return the audit completion state for one scoped session.
  ensureAgentMcpLockInitialized()
  withLock agentMcpLock:
    result = (called: session.completionCalled, report: session.auditReport)

proc mcpRequestMethods*(session: AgentMcpSession): seq[string] =
  ## Return the MCP request methods received for one scoped session.
  ensureAgentMcpLockInitialized()
  withLock agentMcpLock:
    result = session.requestMethods

proc invokeAgentMcpTool*(endpoint, toolName: string, arguments: JsonNode): JsonNode =
  ## Invoke a registered scoped tool in process for component tests.
  let cleanEndpoint = normalizedEndpointBase(endpoint)
  let token = cleanEndpoint.split('/')[^1]
  let session = lookupAgentMcpSession(token)
  if session.isNil:
    raise newException(ValueError, "agent MCP session is not registered")
  if not session.server.toolHandlers.hasKey(toolName):
    raise newException(ValueError, "agent MCP tool is not registered: " & toolName)
  result = session.server.toolHandlers[toolName](arguments)

proc respondWithMcpResult(request: Request, mcpResult: McpResult) =
  ## Serialize one MCPort result as a Streamable HTTP response.
  var headers: httpheaders.HttpHeaders
  headers["content-type"] = "application/json"
  if mcpResult.isError:
    request.respond(200, headers, mcpResult.error.toJson())
  elif mcpResult.response.result == %*{}:
    request.respond(204)
  else:
    request.respond(200, headers, mcpResult.response.toJson())

proc newAgentHttpServer(): mummy.Server =
  ## Create the shared HTTP transport host for scoped agent MCP servers.
  ensureAgentMcpLockInitialized()
  var router: Router
  router.get("/health", proc(request: Request) {.gcsafe.} =
    request.respond(200, body = "ok")
  )
  router.post("/agents/@token/mcp", proc(request: Request) {.gcsafe.} =
    let session = lookupAgentMcpSession(request.pathParams["token"])
    if session.isNil:
      request.respond(404, body = "Unknown or expired agent MCP session")
      return
    var contentType = ""
    for (key, value) in httpheaders.toBase(request.headers):
      if key.toLowerAscii() == "content-type":
        contentType = value.toLowerAscii().strip()
        break
    if not contentType.startsWith("application/json"):
      request.respond(400, body = "Content-Type must start with application/json")
      return
    recordRequestMethod(session, request.body)
    respondWithMcpResult(request, session.server.handleRequest(request.body))
  )
  result = newServer(router, workerThreads = 4)

proc createAgentMcpHost*(): AgentMcpHost =
  ## Allocate a host while leaving Mummy allocations on the serving thread.
  ensureAgentMcpLockInitialized()
  ensureShutdownLockInitialized()
  withLock shutdownLock:
    shutdownRequested = false
  AgentMcpHost()

proc shutdownMonitor(server: mummy.Server) {.thread.} =
  ## Close a listening server through Mummy's documented cross-thread signal.
  withLock shutdownLock:
    while not shutdownRequested:
      wait(shutdownCond, shutdownLock)
  server.close()

proc runHttpServer*(args: ServerThreadArgs) {.thread.} =
  ## Construct and destroy Mummy on its owner thread with bounded HTTP workers.
  let server = newAgentHttpServer()
  args.httpServer.httpServer = server
  var monitorThread: Thread[mummy.Server]
  createThread(monitorThread, shutdownMonitor, server)
  server.serve(Port(args.port), args.address)
  joinThread(monitorThread)
  args.httpServer.httpServer = nil

proc waitForServerReady*(address: string, port: int, timeoutMs: int = ServerReadyTimeoutMs) =
  ## Poll the MCP host health endpoint until it responds or timeout is reached.
  let url = fmt"http://{address}:{port}/health"
  let deadline = epochTime() + float(timeoutMs) / 1000.0
  while epochTime() < deadline:
    try:
      let client = std_httpclient.newHttpClient(timeout = 500)
      defer: client.close()
      let response = client.request(url, httpMethod = std_httpclient.HttpGet)
      if response.code == std_httpclient.Http200:
        return
    except CatchableError:
      sleep(ServerReadyPollIntervalMs)
  raise newException(IOError, fmt"MCP host not ready after {timeoutMs}ms on {address}:{port}")
