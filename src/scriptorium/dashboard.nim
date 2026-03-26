import
  std/[algorithm, options, os, posix, strformat, strutils, times],
  jsony,
  mummy, mummy/routers,
  ./[architect_agent, config, git_ops, logging, pause_flag, shared_state,
      ticket_metadata]

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

const
  RecentOutcomesLimit = 10

type
  QueueItemSummary* = object
    ticketId*: string
    branch*: string
    summary*: string

  MergeOutcome* = object
    ticketId*: string
    outcome*: string
    summary*: string

  QueueResponse* = object
    pending*: seq[QueueItemSummary]
    active*: Option[QueueItemSummary]
    recentOutcomes*: seq[MergeOutcome]

proc parseQueueItemSummary*(content: string): QueueItemSummary =
  ## Parse a merge queue item markdown into a QueueItemSummary.
  let ticketId = parseQueueField(content, "**Ticket ID:**")
  let branch = parseQueueField(content, "**Branch:**")
  let summary = parseQueueField(content, "**Summary:**")
  result = QueueItemSummary(ticketId: ticketId, branch: branch, summary: summary)

proc listPendingQueueItems*(repoPath: string): seq[QueueItemSummary] =
  ## List pending merge queue items from the plan branch.
  let dirRef = PlanBranch & ":" & PlanMergeQueuePendingDir
  let dirResult = runCommandCapture(repoPath, "git", @["show", dirRef])
  if dirResult.exitCode != 0:
    return
  var files: seq[string] = @[]
  for line in dirResult.output.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0 or not trimmed.endsWith(".md"):
      continue
    files.add(trimmed)
  files.sort()
  for filename in files:
    let filePath = PlanMergeQueuePendingDir & "/" & filename
    let fileResult = runCommandCapture(repoPath, "git", @["show", PlanBranch & ":" & filePath])
    if fileResult.exitCode != 0:
      continue
    result.add(parseQueueItemSummary(fileResult.output))

proc getActiveQueueItem*(repoPath: string): Option[QueueItemSummary] =
  ## Read the active merge queue item from the plan branch.
  let activeRef = PlanBranch & ":" & PlanMergeQueueActivePath
  let activeResult = runCommandCapture(repoPath, "git", @["show", activeRef])
  if activeResult.exitCode != 0:
    return none(QueueItemSummary)
  let activePendingPath = activeResult.output.strip()
  if activePendingPath.len == 0:
    return none(QueueItemSummary)
  let fileRef = PlanBranch & ":" & activePendingPath
  let fileResult = runCommandCapture(repoPath, "git", @["show", fileRef])
  if fileResult.exitCode != 0:
    return none(QueueItemSummary)
  result = some(parseQueueItemSummary(fileResult.output))

proc parseMergeOutcome*(ticketContent: string, ticketId: string): Option[MergeOutcome] =
  ## Extract merge outcome from a done ticket's content.
  var inMergeSection = false
  var outcome = ""
  var summary = ""
  for line in ticketContent.splitLines():
    let trimmed = line.strip()
    if trimmed == "## Merge Queue Success":
      inMergeSection = true
      outcome = "success"
      continue
    if trimmed == "## Merge Queue Failure":
      inMergeSection = true
      outcome = "failure"
      continue
    if inMergeSection and trimmed.startsWith("## "):
      break
    if inMergeSection and trimmed.startsWith("- Summary: "):
      summary = trimmed["- Summary: ".len..^1].strip()
  if outcome.len > 0:
    return some(MergeOutcome(ticketId: ticketId, outcome: outcome, summary: summary))

proc getRecentMergeOutcomes*(repoPath: string): seq[MergeOutcome] =
  ## Read the last done tickets and extract merge outcomes.
  let dirRef = PlanBranch & ":" & PlanTicketsDoneDir
  let dirResult = runCommandCapture(repoPath, "git", @["show", dirRef])
  if dirResult.exitCode != 0:
    return
  var files: seq[string] = @[]
  for line in dirResult.output.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0 or not trimmed.endsWith(".md"):
      continue
    files.add(trimmed)
  files.sort(order = SortOrder.Descending)
  for filename in files:
    let filePath = PlanTicketsDoneDir & "/" & filename
    let fileResult = runCommandCapture(repoPath, "git", @["show", PlanBranch & ":" & filePath])
    if fileResult.exitCode != 0:
      continue
    let ticketId = ticketIdFromTicketPath(filename)
    let outcomeOpt = parseMergeOutcome(fileResult.output, ticketId)
    if outcomeOpt.isSome:
      result.add(outcomeOpt.get)
      if result.len >= RecentOutcomesLimit:
        break

proc getApiQueue*(repoPath: string): QueueResponse =
  ## Build the queue response object from plan branch data.
  result.pending = listPendingQueueItems(repoPath)
  result.active = getActiveQueueItem(repoPath)
  result.recentOutcomes = getRecentMergeOutcomes(repoPath)

proc queueHandler(request: Request) =
  ## Handle GET /api/queue and return JSON merge queue state.
  {.cast(gcsafe).}:
    let repoPath = getCurrentDir()
  let queue = getApiQueue(repoPath)
  let body = toJson(queue)
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  request.respond(200, headers, body)

type
  AgentSlotResponse* = object
    role*: string
    ticketId*: string
    areaId*: string
    elapsed*: string
    status*: string

  AgentsResponse* = object
    agents*: seq[AgentSlotResponse]
    maxAgents*: int

proc parseAgentFromTicket*(filename: string, content: string): AgentSlotResponse =
  ## Parse an in-progress ticket into an agent slot response.
  let ticketId = ticketIdFromTicketPath(filename)
  let areaId = parseAreaFromTicketContent(content)
  let worktree = parseWorktreeFromTicketContent(content)
  var elapsed = ""
  if worktree.len > 0 and dirExists(worktree):
    let mtime = getFileInfo(worktree).lastWriteTime
    let secs = (getTime() - mtime).inSeconds
    elapsed = formatUptime(secs)
  result = AgentSlotResponse(
    role: "coder",
    ticketId: ticketId,
    areaId: areaId,
    elapsed: elapsed,
    status: "running",
  )

proc getApiAgents*(repoPath: string): AgentsResponse =
  ## Build the agents response by reading in-progress tickets from the plan branch.
  let cfg = loadConfig(repoPath)
  result.maxAgents = cfg.concurrency.maxAgents
  let dirRef = PlanBranch & ":" & PlanTicketsInProgressDir
  let dirResult = runCommandCapture(repoPath, "git", @["show", dirRef])
  if dirResult.exitCode != 0:
    return
  for line in dirResult.output.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0 or not trimmed.endsWith(".md"):
      continue
    let filePath = PlanTicketsInProgressDir & "/" & trimmed
    let fileResult = runCommandCapture(repoPath, "git", @["show", PlanBranch & ":" & filePath])
    if fileResult.exitCode != 0:
      continue
    result.agents.add(parseAgentFromTicket(trimmed, fileResult.output))

proc agentsHandler(request: Request) =
  ## Handle GET /api/agents and return JSON list of active agent slots.
  {.cast(gcsafe).}:
    let repoPath = getCurrentDir()
  let agents = getApiAgents(repoPath)
  let body = toJson(agents)
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  request.respond(200, headers, body)

type
  SpecResponse* = object
    content*: string

  AreaSummary* = object
    id*: string
    summary*: string

  AreasResponse* = object
    areas*: seq[AreaSummary]

  AreaDetail* = object
    id*: string
    content*: string

proc parseAreaSummary*(filename: string, content: string): AreaSummary =
  ## Build an area summary from a filename and its markdown content.
  let id = filename.replace(".md", "")
  var summary = ""
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.len > 0:
      summary = trimmed
      break
  result = AreaSummary(id: id, summary: summary)

proc getApiSpec*(repoPath: string): SpecResponse =
  ## Read the full spec.md from the plan branch.
  let specRef = PlanBranch & ":" & PlanSpecPath
  let specResult = runCommandCapture(repoPath, "git", @["show", specRef])
  if specResult.exitCode == 0:
    result.content = specResult.output

proc listAreas*(repoPath: string): seq[AreaSummary] =
  ## List all areas from the plan branch with their first-line summaries.
  let dirRef = PlanBranch & ":" & PlanAreasDir & "/"
  let dirResult = runCommandCapture(repoPath, "git", @["show", dirRef])
  if dirResult.exitCode != 0:
    return
  for line in dirResult.output.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0 or not trimmed.endsWith(".md"):
      continue
    let filePath = PlanAreasDir & "/" & trimmed
    let fileResult = runCommandCapture(repoPath, "git", @["show", PlanBranch & ":" & filePath])
    if fileResult.exitCode != 0:
      continue
    result.add(parseAreaSummary(trimmed, fileResult.output))

proc getAreaById*(repoPath: string, areaId: string): Option[AreaDetail] =
  ## Read a single area by ID from the plan branch.
  let fileRef = PlanBranch & ":" & PlanAreasDir & "/" & areaId & ".md"
  let fileResult = runCommandCapture(repoPath, "git", @["show", fileRef])
  if fileResult.exitCode != 0:
    return none(AreaDetail)
  result = some(AreaDetail(id: areaId, content: fileResult.output))

proc specHandler(request: Request) =
  ## Handle GET /api/spec and return JSON with spec content.
  {.cast(gcsafe).}:
    let repoPath = getCurrentDir()
  let spec = getApiSpec(repoPath)
  let body = toJson(spec)
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  request.respond(200, headers, body)

proc areasHandler(request: Request) =
  ## Handle GET /api/areas and return JSON list of area summaries.
  {.cast(gcsafe).}:
    let repoPath = getCurrentDir()
  let resp = AreasResponse(areas: listAreas(repoPath))
  let body = toJson(resp)
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  request.respond(200, headers, body)

proc areaDetailHandler(request: Request) =
  ## Handle GET /api/areas/:id and return JSON area detail or 404.
  {.cast(gcsafe).}:
    let repoPath = getCurrentDir()
  let pathParts = request.uri.split("/")
  if pathParts.len < 4:
    var headers: HttpHeaders
    headers["Content-Type"] = "application/json"
    request.respond(404, headers, """{"error": "area not found"}""")
    return
  let areaId = pathParts[3]
  let detail = getAreaById(repoPath, areaId)
  if detail.isNone:
    var headers: HttpHeaders
    headers["Content-Type"] = "application/json"
    request.respond(404, headers, """{"error": "area not found"}""")
    return
  let body = toJson(detail.get)
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  request.respond(200, headers, body)

const
  ValidLogRoles* = ["coder", "manager", "review", "architect", "audit"]

type
  LogResponse* = object
    role*: string
    id*: string
    content*: string

proc resolveLogDir*(repoPath: string, role: string, id: string): string =
  ## Build the filesystem path to a log directory for the given role and ticket ID.
  result = repoPath / ManagedStateDirName / PlanLogDirName / role / id

proc getLogContent*(repoPath: string, role: string, id: string): Option[LogResponse] =
  ## Read log content for a role and ticket ID, returning none if not found.
  let logDir = resolveLogDir(repoPath, role, id)
  if not dirExists(logDir):
    return none(LogResponse)
  var parts: seq[string]
  for kind, path in walkDir(logDir):
    if kind == pcFile and path.endsWith(".jsonl"):
      parts.add(readFile(path))
  if parts.len == 0:
    for kind, path in walkDir(logDir):
      if kind == pcFile:
        parts.add(readFile(path))
  if parts.len == 0:
    return none(LogResponse)
  let content = parts.join("\n")
  result = some(LogResponse(role: role, id: id, content: content))

proc logsHandler(request: Request) =
  ## Handle GET /api/logs/:role/:id and return JSON log content.
  {.cast(gcsafe).}:
    let repoPath = getCurrentDir()
  let pathParts = request.uri.split("/")
  if pathParts.len < 5:
    var headers: HttpHeaders
    headers["Content-Type"] = "application/json"
    request.respond(404, headers, """{"error": "not found"}""")
    return
  let role = pathParts[3]
  let id = pathParts[4]
  if role notin ValidLogRoles:
    var headers: HttpHeaders
    headers["Content-Type"] = "application/json"
    request.respond(400, headers, """{"error": "invalid role"}""")
    return
  let logOpt = getLogContent(repoPath, role, id)
  if logOpt.isNone:
    var headers: HttpHeaders
    headers["Content-Type"] = "application/json"
    request.respond(404, headers, """{"error": "log not found"}""")
    return
  let body = toJson(logOpt.get)
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
  router.get("/api/queue", queueHandler)
  router.get("/api/agents", agentsHandler)
  router.get("/api/spec", specHandler)
  router.get("/api/areas", areasHandler)
  router.get("/api/areas/*", areaDetailHandler)
  router.get("/api/logs/*/*", logsHandler)
  router.notFoundHandler = notFoundHandler

  let server = newServer(router)
  server.serve(Port(port), host)
