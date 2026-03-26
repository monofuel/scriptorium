import
  std/[options, os, posix, strformat, strutils, times],
  jsony,
  mummy, mummy/routers,
  ./[config, git_ops, logging, pause_flag]

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

proc runDashboard*(repoPath: string) =
  ## Start the blocking mummy HTTP server for the dashboard.
  let cfg = loadConfig(repoPath)
  let host = cfg.dashboard.host
  let port = cfg.dashboard.port
  logInfo(&"Starting dashboard on {host}:{port}")

  var router: Router
  router.get("/", indexHandler)
  router.get("/api/status", statusHandler)
  router.notFoundHandler = notFoundHandler

  let server = newServer(router)
  server.serve(Port(port), host)
