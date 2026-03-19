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
  SubmitPrTestOutputMaxChars = 2000
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

    if active.worktreePath.len == 0:
      {.cast(gcsafe).}:
        logInfo(&"ticket {ticketLabel}: submit_pr pre-check: SKIP (no active worktree)")
      recordSubmitPrSummary(summary, active.ticketId)
      return %*"Merge request enqueued."

    let testStartTime = epochTime()
    let testResult = runRequiredQualityChecks(active.worktreePath)
    let testWallTime = epochTime() - testStartTime
    let testExitCode = testResult.exitCode
    {.cast(gcsafe).}:
      let testWallDuration = formatDuration(testWallTime)
      let testStatus = if testExitCode == 0: "PASS" else: "FAIL"
      let failInfo = if testResult.failedTarget.len > 0: &", failed={testResult.failedTarget}" else: ""
      logInfo(&"ticket {ticketLabel}: submit_pr pre-check: {testStatus} (exit={testExitCode}, wall={testWallDuration}{failInfo})")

    if testExitCode != 0:
      let outputTail = truncateTail(testResult.output.strip(), SubmitPrTestOutputMaxChars)
      let failedOn = if testResult.failedTarget.len > 0: &" on '{testResult.failedTarget}'" else: ""
      return %*(&"Pre-submit quality gate failed{failedOn} (exit={testExitCode}). Fix the failing tests and call submit_pr again.\n\n{outputTail}")

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
          "enum": ["approve", "request_changes"],
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
    if action != "approve" and action != "request_changes":
      return %*"Invalid action. Must be \"approve\" or \"request_changes\"."
    let feedback = if arguments.hasKey("feedback"): arguments["feedback"].getStr() else: ""
    if action == "request_changes" and feedback.len == 0:
      return %*"Feedback is required when action is \"request_changes\"."
    recordReviewDecision(action, feedback)
    %*"Review decision recorded."
  server.registerTool(submitReviewTool, submitReviewHandler)
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
