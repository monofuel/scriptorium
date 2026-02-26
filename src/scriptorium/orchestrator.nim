import
  std/[algorithm, os, osproc, posix, sets, streams, strformat, strutils, tempfiles, uri],
  mcport,
  ./config

const
  PlanBranch = "scriptorium/plan"
  PlanAreasDir = "areas"
  PlanTicketsOpenDir = "tickets/open"
  PlanTicketsInProgressDir = "tickets/in-progress"
  PlanTicketsDoneDir = "tickets/done"
  PlanSpecPath = "spec.md"
  AreaCommitMessage = "scriptorium: update areas from spec"
  TicketCommitMessage = "scriptorium: create tickets from areas"
  AreaFieldPrefix = "**Area:**"
  DefaultLocalEndpoint* = "http://127.0.0.1:8097"
  IdleSleepMs = 200
  OrchestratorServerName = "scriptorium-orchestrator"
  OrchestratorServerVersion = "0.1.0"

type
  OrchestratorEndpoint* = object
    address*: string
    port*: int

  AreaDocument* = object
    path*: string
    content*: string

  ArchitectAreaGenerator* = proc(model: string, spec: string): seq[AreaDocument]

  TicketDocument* = object
    slug*: string
    content*: string

  ManagerTicketGenerator* = proc(model: string, areaPath: string, areaContent: string): seq[TicketDocument]

  ServerThreadArgs = tuple[
    httpServer: HttpMcpServer,
    address: string,
    port: int,
  ]

var shouldRun {.volatile.} = true

proc gitRun(dir: string, args: varargs[string]) =
  ## Run a git subcommand in dir and raise an IOError on non-zero exit.
  let argsSeq = @args
  let allArgs = @["-C", dir] & argsSeq
  let process = startProcess("git", args = allArgs, options = {poUsePath, poStdErrToStdOut})
  let output = process.outputStream.readAll()
  let rc = process.waitForExit()
  process.close()
  if rc != 0:
    let argsStr = argsSeq.join(" ")
    raise newException(IOError, fmt"git {argsStr} failed: {output.strip()}")

proc gitCheck(dir: string, args: varargs[string]): int =
  ## Run a git subcommand in dir and return its exit code.
  let allArgs = @["-C", dir] & @args
  let process = startProcess("git", args = allArgs, options = {poUsePath, poStdErrToStdOut})
  discard process.outputStream.readAll()
  result = process.waitForExit()
  process.close()

proc withPlanWorktree[T](repoPath: string, operation: proc(planPath: string): T): T =
  ## Open a temporary worktree for the plan branch, run operation, then remove it.
  if gitCheck(repoPath, "rev-parse", "--verify", PlanBranch) != 0:
    raise newException(ValueError, "scriptorium/plan branch does not exist")

  let planWorktree = createTempDir("scriptorium_plan_", "", getTempDir())
  removeDir(planWorktree)
  gitRun(repoPath, "worktree", "add", planWorktree, PlanBranch)
  defer:
    discard gitCheck(repoPath, "worktree", "remove", "--force", planWorktree)

  result = operation(planWorktree)

proc loadSpecFromPlanPath(planPath: string): string =
  ## Load spec.md from an existing plan branch worktree path.
  let specPath = planPath / PlanSpecPath
  if not fileExists(specPath):
    raise newException(ValueError, "spec.md does not exist in scriptorium/plan")
  result = readFile(specPath)

proc normalizeAreaPath(rawPath: string): string =
  ## Validate and normalize a relative area path.
  let clean = rawPath.strip()
  if clean.len == 0:
    raise newException(ValueError, "area path cannot be empty")
  if clean.startsWith("/") or clean.startsWith("\\"):
    raise newException(ValueError, fmt"area path must be relative: {clean}")
  if clean.startsWith("..") or clean.contains("/../") or clean.contains("\\..\\"):
    raise newException(ValueError, fmt"area path cannot escape areas directory: {clean}")
  if not clean.toLowerAscii().endsWith(".md"):
    raise newException(ValueError, fmt"area path must be a markdown file: {clean}")
  result = clean

proc normalizeTicketSlug(rawSlug: string): string =
  ## Validate and normalize a ticket slug for filename usage.
  let clean = rawSlug.strip().toLowerAscii()
  if clean.len == 0:
    raise newException(ValueError, "ticket slug cannot be empty")

  var slug = ""
  for ch in clean:
    if ch in {'a'..'z', '0'..'9'}:
      slug.add(ch)
    elif ch in {' ', '-', '_'}:
      if slug.len > 0 and slug[^1] != '-':
        slug.add('-')

  if slug.endsWith("-"):
    slug.setLen(slug.len - 1)
  if slug.len == 0:
    raise newException(ValueError, "ticket slug must contain alphanumeric characters")
  result = slug

proc areaIdFromAreaPath(areaRelPath: string): string =
  ## Derive the area identifier from an area file path.
  result = splitFile(areaRelPath).name

proc parseAreaFromTicketContent(ticketContent: string): string =
  ## Extract the area identifier from a ticket markdown body.
  for line in ticketContent.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith(AreaFieldPrefix):
      result = trimmed[AreaFieldPrefix.len..^1].strip()
      break

proc listMarkdownFiles(basePath: string): seq[string] =
  ## Collect markdown files recursively and return sorted absolute paths.
  if not dirExists(basePath):
    result = @[]
  else:
    for filePath in walkDirRec(basePath):
      if filePath.toLowerAscii().endsWith(".md"):
        result.add(filePath)
    result.sort()

proc collectActiveTicketAreas(planPath: string): HashSet[string] =
  ## Collect area identifiers that currently have open or in-progress tickets.
  result = initHashSet[string]()
  for stateDir in [PlanTicketsOpenDir, PlanTicketsInProgressDir]:
    for ticketPath in listMarkdownFiles(planPath / stateDir):
      let areaId = parseAreaFromTicketContent(readFile(ticketPath))
      if areaId.len > 0:
        result.incl(areaId)

proc areasNeedingTicketsInPlanPath(planPath: string): seq[string] =
  ## Return area files that currently have no open or in-progress tickets.
  let activeAreas = collectActiveTicketAreas(planPath)
  for areaPath in listMarkdownFiles(planPath / PlanAreasDir):
    let relativeAreaPath = relativePath(areaPath, planPath).replace('\\', '/')
    let areaId = areaIdFromAreaPath(relativeAreaPath)
    if not activeAreas.contains(areaId):
      result.add(relativeAreaPath)
  result.sort()

proc areasMissingInPlanPath(planPath: string): bool =
  ## Return true when no area markdown files exist under areas/.
  let areasPath = planPath / PlanAreasDir
  if not dirExists(areasPath):
    result = true
  else:
    var hasAreaFiles = false
    for filePath in walkDirRec(areasPath):
      if filePath.toLowerAscii().endsWith(".md"):
        hasAreaFiles = true
    result = not hasAreaFiles

proc nextTicketId(planPath: string): int =
  ## Compute the next monotonic ticket ID by scanning all ticket states.
  result = 1
  for stateDir in [PlanTicketsOpenDir, PlanTicketsInProgressDir, PlanTicketsDoneDir]:
    for ticketPath in listMarkdownFiles(planPath / stateDir):
      let ticketName = splitFile(ticketPath).name
      let dashPos = ticketName.find('-')
      if dashPos > 0:
        let prefix = ticketName[0..<dashPos]
        if prefix.allCharsInSet(Digits):
          let parsedId = parseInt(prefix)
          if parsedId >= result:
            result = parsedId + 1

proc writeAreasAndCommit(planPath: string, docs: seq[AreaDocument]): bool =
  ## Write generated area files and commit only when contents changed.
  var hasChanges = false
  for doc in docs:
    let relPath = normalizeAreaPath(doc.path)
    let target = planPath / PlanAreasDir / relPath
    createDir(parentDir(target))
    if fileExists(target):
      if readFile(target) != doc.content:
        writeFile(target, doc.content)
        hasChanges = true
    else:
      writeFile(target, doc.content)
      hasChanges = true

  if hasChanges:
    gitRun(planPath, "add", PlanAreasDir)
    if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
      gitRun(planPath, "commit", "-m", AreaCommitMessage)

  result = hasChanges

proc writeTicketsForArea(
  planPath: string,
  areaRelPath: string,
  docs: seq[TicketDocument],
  nextId: var int,
): bool =
  ## Write manager-generated tickets for one area into tickets/open.
  let areaId = areaIdFromAreaPath(areaRelPath)
  var hasChanges = false

  for doc in docs:
    let slug = normalizeTicketSlug(doc.slug)
    let ticketPath = planPath / PlanTicketsOpenDir / fmt"{nextId:04d}-{slug}.md"
    let body = doc.content.strip()
    if body.len == 0:
      raise newException(ValueError, "ticket content cannot be empty")

    let existingArea = parseAreaFromTicketContent(body)
    var ticketContent = body
    if existingArea.len == 0:
      ticketContent &= "\n\n" & AreaFieldPrefix & " " & areaId & "\n"
    elif existingArea != areaId:
      raise newException(ValueError, fmt"ticket area '{existingArea}' does not match area '{areaId}'")
    else:
      ticketContent &= "\n"

    writeFile(ticketPath, ticketContent)
    hasChanges = true
    inc nextId

  result = hasChanges

proc parsePort(rawPort: string, scheme: string): int =
  ## Parse the port value from a URI, falling back to scheme defaults.
  if rawPort.len > 0:
    result = parseInt(rawPort)
  elif scheme == "https":
    result = 443
  else:
    result = 80

  if result < 1 or result > 65535:
    raise newException(ValueError, fmt"invalid endpoint port: {result}")

proc parseEndpoint*(endpointUrl: string): OrchestratorEndpoint =
  ## Parse the orchestrator HTTP endpoint from a URL.
  let clean = endpointUrl.strip()
  let resolved = if clean.len > 0: clean else: DefaultLocalEndpoint
  let parsed = parseUri(resolved)

  if parsed.scheme.len == 0:
    raise newException(ValueError, fmt"invalid endpoint URL (missing scheme): {resolved}")
  if parsed.hostname.len == 0:
    raise newException(ValueError, fmt"invalid endpoint URL (missing hostname): {resolved}")

  result = OrchestratorEndpoint(
    address: parsed.hostname,
    port: parsePort(parsed.port, parsed.scheme),
  )

proc loadOrchestratorEndpoint*(repoPath: string): OrchestratorEndpoint =
  ## Load and parse the orchestrator endpoint from repo configuration.
  let cfg = loadConfig(repoPath)
  result = parseEndpoint(cfg.endpoints.local)

proc loadSpecFromPlan*(repoPath: string): string =
  ## Load spec.md by opening the scriptorium/plan branch in a temporary worktree.
  result = withPlanWorktree(repoPath, proc(planPath: string): string =
    loadSpecFromPlanPath(planPath)
  )

proc areasMissing*(repoPath: string): bool =
  ## Return true when the plan branch has no area markdown files.
  result = withPlanWorktree(repoPath, proc(planPath: string): bool =
    areasMissingInPlanPath(planPath)
  )

proc areasNeedingTickets*(repoPath: string): seq[string] =
  ## Return area files that are eligible for manager ticket generation.
  result = withPlanWorktree(repoPath, proc(planPath: string): seq[string] =
    areasNeedingTicketsInPlanPath(planPath)
  )

proc syncAreasFromSpec*(repoPath: string, generateAreas: ArchitectAreaGenerator): bool =
  ## Generate and persist areas when plan/areas has no markdown files.
  if generateAreas.isNil:
    raise newException(ValueError, "architect area generator is required")

  let cfg = loadConfig(repoPath)
  result = withPlanWorktree(repoPath, proc(planPath: string): bool =
    let missing = areasMissingInPlanPath(planPath)
    if missing:
      let spec = loadSpecFromPlanPath(planPath)
      let docs = generateAreas(cfg.models.architect, spec)
      discard writeAreasAndCommit(planPath, docs)
      true
    else:
      false
  )

proc syncTicketsFromAreas*(repoPath: string, generateTickets: ManagerTicketGenerator): bool =
  ## Generate and persist tickets for areas without active work.
  if generateTickets.isNil:
    raise newException(ValueError, "manager ticket generator is required")

  let cfg = loadConfig(repoPath)
  result = withPlanWorktree(repoPath, proc(planPath: string): bool =
    let areasToProcess = areasNeedingTicketsInPlanPath(planPath)
    if areasToProcess.len == 0:
      false
    else:
      var nextId = nextTicketId(planPath)
      var hasChanges = false
      for areaRelPath in areasToProcess:
        let areaContent = readFile(planPath / areaRelPath)
        let docs = generateTickets(cfg.models.coding, areaRelPath, areaContent)
        if writeTicketsForArea(planPath, areaRelPath, docs, nextId):
          hasChanges = true

      if hasChanges:
        gitRun(planPath, "add", PlanTicketsOpenDir)
        if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
          gitRun(planPath, "commit", "-m", TicketCommitMessage)
      hasChanges
  )

proc createOrchestratorServer*(): HttpMcpServer =
  ## Create the orchestrator MCP HTTP server.
  let server = newMcpServer(OrchestratorServerName, OrchestratorServerVersion)
  result = newHttpMcpServer(server, logEnabled = false)

proc handleCtrlC() {.noconv.} =
  ## Stop the orchestrator loop on Ctrl+C.
  shouldRun = false

proc handlePosixSignal(signalNumber: cint) {.noconv.} =
  ## Stop the orchestrator loop on SIGINT/SIGTERM.
  discard signalNumber
  shouldRun = false

proc installSignalHandlers() =
  ## Install signal handlers used by the orchestrator run loop.
  setControlCHook(handleCtrlC)
  posix.signal(SIGINT, handlePosixSignal)
  posix.signal(SIGTERM, handlePosixSignal)

proc runHttpServer(args: ServerThreadArgs) {.thread.} =
  ## Run the MCP HTTP server in a background thread.
  args.httpServer.serve(args.port, args.address)

proc runOrchestratorLoop(httpServer: HttpMcpServer, endpoint: OrchestratorEndpoint, maxTicks: int) =
  ## Start HTTP transport and execute the orchestrator idle event loop.
  shouldRun = true
  installSignalHandlers()

  var serverThread: Thread[ServerThreadArgs]
  createThread(serverThread, runHttpServer, (httpServer, endpoint.address, endpoint.port))

  var ticks = 0
  while shouldRun:
    if maxTicks >= 0 and ticks >= maxTicks:
      break
    sleep(IdleSleepMs)
    inc ticks

  shouldRun = false
  httpServer.close()
  joinThread(serverThread)

proc runOrchestratorForTicks*(repoPath: string, maxTicks: int) =
  ## Run the orchestrator loop for a bounded number of ticks. Used by tests.
  let endpoint = loadOrchestratorEndpoint(repoPath)
  let httpServer = createOrchestratorServer()
  runOrchestratorLoop(httpServer, endpoint, maxTicks)

proc runOrchestrator*(repoPath: string) =
  ## Start the orchestrator daemon with HTTP MCP and an idle event loop.
  let endpoint = loadOrchestratorEndpoint(repoPath)
  echo fmt"scriptorium: orchestrator listening on http://{endpoint.address}:{endpoint.port}"
  let httpServer = createOrchestratorServer()
  runOrchestratorLoop(httpServer, endpoint, -1)
