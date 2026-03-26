import
  std/[options, os, posix, strformat, strutils, times],
  jsony,
  mummy, mummy/routers,
  ./[config, git_ops, logging, pause_flag, ticket_metadata]

type
  DashboardStatus* = object
    pidAlive*: bool
    uptime*: Option[string]
    paused*: bool
    loopIteration*: int

const
  HtmxJs = "// htmx placeholder"
  DashboardHtml = """<!DOCTYPE html>
<html>
<head>
  <title>scriptorium dashboard</title>
  <script>""" & HtmxJs & """</script>
</head>
<body>
  <div id="app">Dashboard loading...</div>
</body>
</html>"""
  NotFoundJson = """{"error": "not found"}"""

proc indexHandler(request: Request) =
  ## Serve the main dashboard HTML page.
  var headers: HttpHeaders
  headers["Content-Type"] = "text/html"
  request.respond(200, headers, DashboardHtml)

proc notFoundHandler(request: Request) =
  ## Return a 404 JSON response for unknown routes.
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  request.respond(404, headers, NotFoundJson)

proc formatUptime*(seconds: int64): string =
  ## Format a duration in seconds as a human-readable string.
  let days = seconds div 86400
  let hours = (seconds mod 86400) div 3600
  let mins = (seconds mod 3600) div 60
  let secs = seconds mod 60
  if days > 0:
    result = &"{days}d {hours}h {mins}m {secs}s"
  elif hours > 0:
    result = &"{hours}h {mins}m {secs}s"
  elif mins > 0:
    result = &"{mins}m {secs}s"
  else:
    result = &"{secs}s"

proc parseIterationCount*(gitShowOutput: string): int =
  ## Parse the highest iteration number from iteration log content.
  var highest = 0
  for line in gitShowOutput.splitLines():
    if line.startsWith("## Iteration "):
      let numStr = line[len("## Iteration ")..^1].strip()
      try:
        let num = parseInt(numStr)
        if num > highest:
          highest = num
      except ValueError:
        discard
  result = highest

proc getApiStatus*(repoPath: string): DashboardStatus =
  ## Build the dashboard status object by checking PID, pause flag, and iteration log.
  var status: DashboardStatus
  status.paused = isPaused(repoPath)

  let pidPath = orchestratorPidPath(repoPath)
  if fileExists(pidPath):
    let pidStr = readFile(pidPath).strip()
    try:
      let pid = parseInt(pidStr)
      let rc = kill(Pid(pid), cint(0))
      let alive = rc == 0 or (rc == -1 and errno == EPERM)
      status.pidAlive = alive
      if alive:
        let mtime = getFileInfo(pidPath).lastWriteTime
        let elapsed = (getTime() - mtime).inSeconds
        status.uptime = some(formatUptime(elapsed))
    except ValueError:
      discard

  let iterResult = runCommandCapture(repoPath, "git", @["show", PlanBranch & ":iteration_log.md"])
  if iterResult.exitCode == 0:
    status.loopIteration = parseIterationCount(iterResult.output)

  result = status

proc statusHandler(request: Request) =
  ## Handle GET /api/status and return JSON response.
  {.cast(gcsafe).}:
    let repoPath = getCurrentDir()
  let status = getApiStatus(repoPath)
  let body = toJson(status)
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  request.respond(200, headers, body)

type
  TicketSummary* = object
    id*: string
    area*: string
    title*: string
    state*: string

  TicketDetail* = object
    id*: string
    area*: string
    title*: string
    state*: string
    content*: string

  TicketListResponse* = object
    open*: seq[TicketSummary]
    inProgress*: seq[TicketSummary]
    done*: seq[TicketSummary]

proc parseTitleFromTicketContent*(content: string): string =
  ## Extract the title from the first markdown heading in ticket content.
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("# "):
      result = trimmed[2..^1].strip()
      break

proc parseTicketSummary*(filename: string, content: string, state: string): TicketSummary =
  ## Build a ticket summary from a filename, its markdown content, and state.
  let ticketId = ticketIdFromTicketPath(filename)
  let area = parseAreaFromTicketContent(content)
  let title = parseTitleFromTicketContent(content)
  result = TicketSummary(id: ticketId, area: area, title: title, state: state)

proc listTicketsInState(repoPath: string, state: string): seq[TicketSummary] =
  ## List all tickets in the given state directory from the plan branch.
  let dirPath = PlanBranch & ":tickets/" & state
  let dirResult = runCommandCapture(repoPath, "git", @["show", dirPath])
  if dirResult.exitCode != 0:
    return
  for line in dirResult.output.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0 or not trimmed.endsWith(".md"):
      continue
    let filePath = "tickets/" & state & "/" & trimmed
    let fileResult = runCommandCapture(repoPath, "git", @["show", PlanBranch & ":" & filePath])
    if fileResult.exitCode != 0:
      continue
    result.add(parseTicketSummary(trimmed, fileResult.output, state))

proc findTicketById(repoPath: string, ticketId: string): Option[TicketDetail] =
  ## Search all ticket state directories for a ticket matching the given ID.
  let states = ["open", "in-progress", "done"]
  for state in states:
    let dirPath = PlanBranch & ":tickets/" & state
    let dirResult = runCommandCapture(repoPath, "git", @["show", dirPath])
    if dirResult.exitCode != 0:
      continue
    for line in dirResult.output.splitLines():
      let trimmed = line.strip()
      if trimmed.len == 0 or not trimmed.endsWith(".md"):
        continue
      let fileId = ticketIdFromTicketPath(trimmed)
      if fileId != ticketId:
        continue
      let filePath = "tickets/" & state & "/" & trimmed
      let fileResult = runCommandCapture(repoPath, "git", @["show", PlanBranch & ":" & filePath])
      if fileResult.exitCode != 0:
        continue
      let area = parseAreaFromTicketContent(fileResult.output)
      let title = parseTitleFromTicketContent(fileResult.output)
      return some(TicketDetail(
        id: fileId, area: area, title: title,
        state: state, content: fileResult.output,
      ))

proc ticketsHandler(request: Request) =
  ## Handle GET /api/tickets and return JSON list of tickets by state.
  {.cast(gcsafe).}:
    let repoPath = getCurrentDir()
  var resp: TicketListResponse
  resp.open = listTicketsInState(repoPath, "open")
  resp.inProgress = listTicketsInState(repoPath, "in-progress")
  resp.done = listTicketsInState(repoPath, "done")
  let body = toJson(resp)
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  request.respond(200, headers, body)

proc ticketDetailHandler(request: Request) =
  ## Handle GET /api/tickets/:id and return JSON ticket detail or 404.
  {.cast(gcsafe).}:
    let repoPath = getCurrentDir()
  let pathParts = request.uri.split("/")
  if pathParts.len < 4:
    var headers: HttpHeaders
    headers["Content-Type"] = "application/json"
    request.respond(404, headers, """{"error": "ticket not found"}""")
    return
  let ticketId = pathParts[3]
  let detail = findTicketById(repoPath, ticketId)
  if detail.isNone:
    var headers: HttpHeaders
    headers["Content-Type"] = "application/json"
    request.respond(404, headers, """{"error": "ticket not found"}""")
    return
  let body = toJson(detail.get)
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  request.respond(200, headers, body)

proc runDashboard*(repoPath: string) =
  ## Start the blocking mummy HTTP server for the dashboard.
  let cfg = loadConfig(repoPath)
  let host = cfg.dashboard.host
  let port = cfg.dashboard.port
  logInfo(&"Starting dashboard on {host}:{port}")

  var router: Router
  router.get("/", indexHandler)
  router.get("/api/status", statusHandler)
  router.get("/api/tickets", ticketsHandler)
  router.get("/api/tickets/*", ticketDetailHandler)
  router.notFoundHandler = notFoundHandler

  let server = newServer(router)
  server.serve(Port(port), host)
