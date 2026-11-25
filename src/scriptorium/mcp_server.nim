import
  std/[json, locks, options, os, strformat, strutils, tables, times],
  std/httpclient as std_httpclient,
  jsony,
  mcport,
  mummy,
  mummy/routers,
  webby/httpheaders,
  ./[agent_sessions, mcp_session_store, project_reader, text_encoding]

const
  OrchestratorServerName = "scriptorium-orchestrator"
  OrchestratorServerVersion = "0.1.0"
  AgentMcpRoutePrefix = "/agents/"
  AgentMcpTokenBytes = 32
  ReviewFeedbackMaxBytes* = 4096
  ReviewTruncationMarker* = "... [truncated]"
  ServerReadyTimeoutMs* = 5000
  ServerReadyPollIntervalMs = 50
  MaxRecordedMethods = 128
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
    amrProjectRead = "project-read"

  AgentMcpSession* = ref object
    token*: string
    endpoint*: string
    role*: AgentMcpRole
    server*: McpServer
    ticketId*: string
    branch*: string
    worktree*: string
    areaId*: string
    repoPath: string
    planPath: string
    terminalCompletion: string
    terminalMethods: string

  AgentMcpHost* = ref object
    httpServer*: mummy.Server

  ServerThreadArgs* = tuple[
    httpServer: AgentMcpHost,
    address: string,
    port: int,
  ]

var
  shutdownLock: Lock
  shutdownCond: Cond
  shutdownLockInitialized = false
  shutdownRequested = false

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

proc registerAgentMcpSession(session: AgentMcpSession, endpoint: string,
    completion = "{\"called\":false}") =
  ## Register serialized metadata without sharing the calling thread's server or closures.
  let endpointBase = normalizedEndpointBase(endpoint)
  session.token = newAgentMcpToken()
  session.endpoint = endpointBase & AgentMcpRoutePrefix & session.token
  let descriptor = $(%*{"role": $session.role, "ticketId": session.ticketId,
    "branch": session.branch, "worktree": session.worktree, "areaId": session.areaId,
    "repoPath": session.repoPath, "planPath": session.planPath})
  createMcpRecord(session.token, McpSessionRecord(descriptor: descriptor,
    completion: completion, methods: "[]", initialized: session.server.initialized))

proc unregisterAgentMcpSession*(session: AgentMcpSession) =
  ## Remove one scoped MCP session so its endpoint can no longer be called.
  if session.isNil or session.token.len == 0:
    return
  let final = expireMcpRecord(session.token)
  if final.isSome:
    session.terminalCompletion = final.get().completion
    session.terminalMethods = final.get().methods
  session.server = nil

proc lookupAgentMcpSession(token: string): AgentMcpSession {.gcsafe.} =
  ## Construct a thread-local handle from copied descriptor bytes, never a shared traced reference.
  let record = readMcpRecord(token)
  if record.isNone: return
  let descriptor = parseJson(record.get().descriptor)
  result = AgentMcpSession(token: token,
    role: parseEnum[AgentMcpRole](descriptor["role"].getStr()),
    ticketId: descriptor["ticketId"].getStr(), branch: descriptor["branch"].getStr(),
    worktree: descriptor["worktree"].getStr(), areaId: descriptor["areaId"].getStr(),
    repoPath: descriptor["repoPath"].getStr(), planPath: descriptor["planPath"].getStr())

proc recordCompletion(session: AgentMcpSession, completion: JsonNode,
    persist: proc() {.gcsafe.} = nil) {.gcsafe.} =
  ## Record the first completion call for a session and ignore later duplicates.
  updateMcpRecord(session.token, proc(record: var McpSessionRecord) {.gcsafe.} =
    ## Persist durable coding completion before publishing the first accepted record.
    if parseJson(record.completion)["called"].getBool(): return
    if not persist.isNil: persist()
    record.completion = $completion)

proc recordRequestMethod(session: AgentMcpSession, requestBody: string) {.gcsafe.} =
  ## Record one MCP request method for transport diagnostics.
  var requestNode: JsonNode
  try: requestNode = parseJson(requestBody)
  except JsonParsingError: return
  if requestNode.kind != JObject or requestNode{"method"}.isNil or requestNode["method"].kind != JString: return
  let methodName = requestNode["method"].getStr()
  updateMcpRecord(session.token, proc(record: var McpSessionRecord) {.gcsafe.} =
    ## Bound diagnostics while leaving malformed input to MCPort's structured parser.
    var methods = parseJson(record.methods)
    if methods.len < MaxRecordedMethods: methods.add(%methodName)
    record.methods = $methods)

proc codingReceiptPath(worktree: string): string =
  ## Locate the durable completion receipt inside managed ticket state.
  runtimeStateDirectory(worktree) / "submission.json"

proc acknowledgeCodingSubmission*(session: AgentMcpSession) =
  ## Mark a durable receipt consumed after its merge-queue transition commits.
  let completion = readMcpRecord(session.token)
  let state = parseJson(if completion.isSome: completion.get().completion else: session.terminalCompletion)
  let content = $(%*{"ticketId": session.ticketId, "branch": session.branch,
    "summary": state{"summary"}.getStr(), "pending": false})
  atomicRuntimeWrite(codingReceiptPath(session.worktree), content)

proc configureCodingSession(session: AgentMcpSession) =
  ## Build coding tools entirely on the current request or caller thread.
  let
    receiptPath = codingReceiptPath(session.worktree)
    ticketId = session.ticketId
    branch = session.branch
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
    recordCompletion(session, %*{"called": true, "summary": summary}, proc() {.gcsafe.} =
      atomicRuntimeWrite(receiptPath, $(%*{"ticketId": ticketId, "branch": branch,
        "summary": summary, "pending": true}))
    )
    %*"Merge request recorded."
  session.server.registerTool(tool, handler)

proc configureManagerSession(session: AgentMcpSession) =
  ## Build manager tools entirely on the current request or caller thread.
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
    recordCompletion(session, %*{"called": true, "tickets": tickets})
    %*"Tickets recorded."
  session.server.registerTool(tool, handler)

proc configureReviewerSession(session: AgentMcpSession) =
  ## Build reviewer tools entirely on the current request or caller thread.
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
    if arguments.kind != JObject or not arguments.hasKey("action") or
        arguments["action"].kind != JString:
      return %*"A string action is required."
    for key in arguments.keys:
      if key notin ["action", "feedback"]:
        return %*"Unexpected review argument."
    if arguments.hasKey("feedback") and arguments["feedback"].kind != JString:
      return %*"Feedback must be a string."
    let action = arguments["action"].getStr()
    if action != "approve" and action != "approve_with_warnings" and action != "request_changes":
      return %*"Invalid action. Must be \"approve\", \"approve_with_warnings\", or \"request_changes\"."
    var feedback = if arguments.hasKey("feedback"): arguments["feedback"].getStr() else: ""
    if action == "request_changes" and feedback.strip().len == 0:
      return %*"Feedback is required when action is \"request_changes\"."
    if feedback.len > ReviewFeedbackMaxBytes:
      let textLength = ReviewFeedbackMaxBytes - ReviewTruncationMarker.len
      feedback = utf8Prefix(feedback, textLength) & ReviewTruncationMarker
    recordCompletion(session, %*{"called": true, "action": action, "feedback": feedback})
    %*"Review decision recorded."
  session.server.registerTool(tool, handler)

proc configureAuditSession(session: AgentMcpSession) =
  ## Build audit tools entirely on the current request or caller thread.
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
    recordCompletion(session, %*{"called": true, "report": report})
    %*"Audit report recorded."
  session.server.registerTool(tool, handler)

proc configureSession(session: AgentMcpSession) =
  ## Construct a local MCPort server without transferring server graphs or handler closures between threads.
  if session.role == amrProjectRead:
    session.server = newProjectReadServer(session.repoPath, session.planPath)
  else:
    session.server = newMcpServer(OrchestratorServerName & "-" & $session.role, OrchestratorServerVersion)
    case session.role
    of amrCoding: configureCodingSession(session)
    of amrManager: configureManagerSession(session)
    of amrReviewer: configureReviewerSession(session)
    of amrAudit: configureAuditSession(session)
    else: discard
  let record = readMcpRecord(session.token)
  if record.isSome: session.server.initialized = record.get().initialized

proc newCodingMcpSession*(endpoint, ticketId, branch, worktree: string): AgentMcpSession =
  ## Register a coding capability and restore only its matching pending durable receipt.
  result = AgentMcpSession(role: amrCoding, ticketId: ticketId, branch: branch, worktree: worktree)
  var completion = %*{"called": false}
  let receiptPath = codingReceiptPath(worktree)
  if fileExists(receiptPath):
    let receipt = parseFile(receiptPath)
    if receipt["ticketId"].getStr() == ticketId and receipt["branch"].getStr() == branch and receipt["pending"].getBool():
      completion = %*{"called": true, "summary": receipt["summary"]}
  configureSession(result)
  registerAgentMcpSession(result, endpoint, $completion)

proc newManagerMcpSession*(endpoint, areaId: string): AgentMcpSession =
  ## Register a manager capability and construct its caller-local catalog.
  result = AgentMcpSession(role: amrManager, areaId: areaId)
  configureSession(result)
  registerAgentMcpSession(result, endpoint)

proc newReviewerMcpSession*(endpoint, ticketId: string): AgentMcpSession =
  ## Register a reviewer capability and construct its caller-local catalog.
  result = AgentMcpSession(role: amrReviewer, ticketId: ticketId)
  configureSession(result)
  registerAgentMcpSession(result, endpoint)

proc newAuditMcpSession*(endpoint: string): AgentMcpSession =
  ## Register an audit capability and construct its caller-local catalog.
  result = AgentMcpSession(role: amrAudit)
  configureSession(result)
  registerAgentMcpSession(result, endpoint)

proc completionState(session: AgentMcpSession): JsonNode =
  ## Read a local copy of active state or the final snapshot retained when this handle expired.
  let record = readMcpRecord(session.token)
  let serialized = if record.isSome: record.get().completion else: session.terminalCompletion
  if serialized.len == 0: return %*{"called": false}
  parseJson(serialized)

proc codingSubmission*(session: AgentMcpSession): tuple[called: bool, summary: string] =
  ## Return the coding completion state for one scoped session.
  let state = completionState(session)
  result = (called: state["called"].getBool(), summary: state{"summary"}.getStr())

proc managerSubmission*(session: AgentMcpSession): tuple[called: bool, tickets: seq[string]] =
  ## Return the manager completion state for one scoped session.
  let state = completionState(session)
  result.called = state["called"].getBool()
  if not state{"tickets"}.isNil:
    for ticket in state["tickets"]: result.tickets.add(ticket.getStr())

proc reviewerSubmission*(session: AgentMcpSession): tuple[called: bool, action: string, feedback: string] =
  ## Return the reviewer completion state for one scoped session.
  let state = completionState(session)
  result = (called: state["called"].getBool(), action: state{"action"}.getStr(), feedback: state{"feedback"}.getStr())

proc auditSubmission*(session: AgentMcpSession): tuple[called: bool, report: string] =
  ## Return the audit completion state for one scoped session.
  let state = completionState(session)
  result = (called: state["called"].getBool(), report: state{"report"}.getStr())

proc newProjectReadMcpSession*(endpoint, repoPath, planPath: string): AgentMcpSession =
  ## Register a project-scoped read capability, with no workflow completion or mutating tools.
  result = AgentMcpSession(role: amrProjectRead, repoPath: repoPath, planPath: planPath)
  configureSession(result)
  registerAgentMcpSession(result, endpoint)

proc mcpRequestMethods*(session: AgentMcpSession): seq[string] =
  ## Return the MCP request methods received for one scoped session.
  let record = readMcpRecord(session.token)
  let serialized = if record.isSome: record.get().methods else: session.terminalMethods
  if serialized.len > 0:
    for item in parseJson(serialized): result.add(item.getStr())

proc invokeAgentMcpTool*(endpoint, toolName: string, arguments: JsonNode): JsonNode =
  ## Invoke a registered scoped tool in process for component tests.
  let cleanEndpoint = normalizedEndpointBase(endpoint)
  let token = cleanEndpoint.split('/')[^1]
  let session = lookupAgentMcpSession(token)
  if session.isNil:
    raise newException(ValueError, "agent MCP session is not registered")
  configureSession(session)
  defer: session.server = nil
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
    configureSession(session)
    defer: session.server = nil
    try:
      recordRequestMethod(session, request.body)
    except McpSessionExpiredError:
      request.respond(404, body = "Unknown or expired agent MCP session")
      return
    let response = session.server.handleRequest(request.body)
    if session.server.initialized:
      markMcpInitialized(session.token)
    respondWithMcpResult(request, response)
  )
  result = newServer(router, workerThreads = 4)

proc createAgentMcpHost*(): AgentMcpHost =
  ## Allocate a host while leaving Mummy allocations on the serving thread.
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
