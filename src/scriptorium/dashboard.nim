import
  std/[strformat],
  mummy, mummy/routers,
  ./[config, logging]

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

proc runDashboard*(repoPath: string) =
  ## Start the blocking mummy HTTP server for the dashboard.
  let cfg = loadConfig(repoPath)
  let host = cfg.dashboard.host
  let port = cfg.dashboard.port
  logInfo(&"Starting dashboard on {host}:{port}")

  var router: Router
  router.get("/", indexHandler)
  router.notFoundHandler = notFoundHandler

  let server = newServer(router)
  server.serve(Port(port), host)
