import
  std/[httpclient, json, locks, os, strformat, strutils, times],
  mcport,
  mummy,
  ./[git_ops, logging, merge_queue, output_formatting, prompt_builders, shared_state]

const
  OrchestratorServerName = "scriptorium-orchestrator"
  OrchestratorServerVersion = "0.1.0"
  BuildCommitHash* = block:
    let fromEnv = staticExec("echo $BUILD_COMMIT").strip()
    if fromEnv.len > 0: fromEnv
    else: staticExec("git rev-parse --short HEAD 2>/dev/null").strip()
  ServerReadyTimeoutMs* = 5000
  ServerReadyPollIntervalMs = 50

type
  ServerThreadArgs* = tuple[
    httpServer: HttpMcpServer,
    address: string,
    port: int,
  ]

var
  shutdownLock: Lock
  shutdownCond: Cond
  shutdownLockInitialized = false

proc ensureShutdownLockInitialized*() =
  ## Initialize the shutdown coordination lock and condition variable.
  if not shutdownLockInitialized:
    initLock(shutdownLock)
    initCond(shutdownCond)
    shutdownLockInitialized = true

proc signalServerShutdown*() =
  ## Signal the server shutdown monitor to close the HTTP server.
  acquire(shutdownLock)
  signal(shutdownCond)
  release(shutdownLock)

proc createOrchestratorServer*(): HttpMcpServer =
  ## Create the orchestrator MCP HTTP server.
  ensureSubmitPrLockInitialized()
  let server = newMcpServer(OrchestratorServerName, OrchestratorServerVersion)
  let submitPrTool = McpTool(
    name: "submit_pr",
    description: "Signal that ticket work is complete and ready for merge queue",
    inputSchema: %*{
      "type": "object",
      "properties": {
        "summary": {
          "type": "string",
          "description": "Short summary of changes"
        },
        "ticket_id": {
          "type": "string",
          "description": "Ticket ID for this submission (optional, used in parallel mode)"
        }
      },
      "required": ["summary"]
    },
  )
  let submitPrHandler: ToolHandler = proc(arguments: JsonNode): JsonNode {.gcsafe.} =
    let summary = arguments["summary"].getStr()
    let reqTicketId = if arguments.hasKey("ticket_id"): arguments["ticket_id"].getStr() else: ""
    let active = getActiveTicketWorktree(reqTicketId)
    let ticketLabel = if active.ticketId.len > 0: active.ticketId else: "unknown"

    # Record summary immediately so the orchestrator can consume it as soon as
    # the agent exits.  Quality checks run later in the merge queue — if they
    # fail the ticket is reopened and a new agent session handles it.
    {.cast(gcsafe).}:
      logInfo(&"ticket {ticketLabel}: submit_pr accepted (quality checks run in merge queue)")
    recordSubmitPrSummary(summary, active.ticketId)
    %*"Merge request enqueued."
  server.registerTool(submitPrTool, submitPrHandler)
  let submitReviewTool = McpTool(
    name: "submit_review",
    description: "Submit a review decision for the current ticket",
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
          "description": "Feedback for the review (required when action is request_changes)"
        }
      },
      "required": ["action"]
    },
  )
  let submitReviewHandler: ToolHandler = proc(arguments: JsonNode): JsonNode {.gcsafe.} =
    let action = arguments["action"].getStr()
    if action != "approve" and action != "approve_with_warnings" and action != "request_changes":
      return %*"Invalid action. Must be \"approve\", \"approve_with_warnings\", or \"request_changes\"."
    let feedback = if arguments.hasKey("feedback"): arguments["feedback"].getStr() else: ""
    if action == "request_changes" and feedback.len == 0:
      return %*"Feedback is required when action is \"request_changes\"."
    recordReviewDecision(action, feedback)
    %*"Review decision recorded."
  server.registerTool(submitReviewTool, submitReviewHandler)
  let submitTicketsTool = McpTool(
    name: "submit_tickets",
    description: "Submit generated tickets for an area to the orchestrator",
    inputSchema: %*{
      "type": "object",
      "properties": {
        "area_id": {
          "type": "string",
          "description": "Area ID these tickets belong to"
        },
        "tickets": {
          "type": "array",
          "items": {"type": "string"},
          "description": "Array of ticket markdown content strings"
        }
      },
      "required": ["area_id", "tickets"]
    },
  )
  let submitTicketsHandler: ToolHandler = proc(arguments: JsonNode): JsonNode {.gcsafe.} =
    let areaId = arguments["area_id"].getStr()
    var tickets: seq[string]
    for item in arguments["tickets"]:
      tickets.add(item.getStr())
    let ticketCount = tickets.len
    {.cast(gcsafe).}:
      logInfo(&"manager {areaId}: submit_tickets accepted ({ticketCount} tickets)")
    recordSubmitTickets(areaId, tickets)
    %*"Tickets recorded."
  server.registerTool(submitTicketsTool, submitTicketsHandler)
  result = newHttpMcpServer(server, logEnabled = false)

proc shutdownMonitor(server: mummy.Server) {.thread.} =
  ## Wait for the shutdown signal then return (do not call server.close()).
  ## Mummy's destroy path has a use-after-free bug that causes flaky SIGSEGV
  ## during deallocShared, so we let the OS reclaim resources on exit instead.
  acquire(shutdownLock)
  while shouldRun:
    wait(shutdownCond, shutdownLock)
  release(shutdownLock)

proc runHttpServer*(args: ServerThreadArgs) {.thread.} =
  ## Run the MCP HTTP server in a background thread with coordinated shutdown.
  ensureShutdownLockInitialized()
  var monitorThread: Thread[mummy.Server]
  createThread(monitorThread, shutdownMonitor, args.httpServer.httpServer)
  args.httpServer.serve(args.port, args.address)
  joinThread(monitorThread)

proc waitForServerReady*(address: string, port: int, timeoutMs: int = ServerReadyTimeoutMs) =
  ## Poll the MCP endpoint until it responds or timeout is reached.
  let url = fmt"http://{address}:{port}/mcp"
  let deadline = epochTime() + float(timeoutMs) / 1000.0
  while epochTime() < deadline:
    try:
      let client = newHttpClient(timeout = 500)
      defer: client.close()
      discard client.request(url, httpMethod = HttpGet)
      logInfo(fmt"MCP server ready on {address}:{port}")
      return
    except:
      sleep(ServerReadyPollIntervalMs)
  logWarn(fmt"MCP server not ready after {timeoutMs}ms, proceeding anyway")
