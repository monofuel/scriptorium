import
  std/[os, sets, strformat, strutils, tables],
  ./[logging, shared_state, ticket_metadata]

type
  DependencyGraph* = Table[string, seq[string]]

proc buildDependencyGraph*(planPath: string): DependencyGraph =
  ## Build a directed graph from open and in-progress tickets using Depends fields.
  result = initTable[string, seq[string]]()
  for stateDir in [PlanTicketsOpenDir, PlanTicketsInProgressDir]:
    let dirPath = planPath / stateDir
    if not dirExists(dirPath):
      continue
    for ticketPath in listMarkdownFiles(dirPath):
      let rel = stateDir / extractFilename(ticketPath)
      let ticketId = ticketIdFromTicketPath(rel)
      let content = readFile(ticketPath)
      let deps = parseDependsFromTicketContent(content)
      result[ticketId] = deps

proc detectCycles*(graph: DependencyGraph): seq[seq[string]] =
  ## Detect all cycles in a dependency graph using DFS-based cycle detection.
  ## Returns a sequence of cycles, each represented as a path of ticket IDs.
  var visited = initHashSet[string]()
  var onStack = initHashSet[string]()
  var path: seq[string]

  proc dfs(node: string, graph: DependencyGraph, cycles: var seq[seq[string]]) =
    ## Depth-first search to find cycles.
    visited.incl(node)
    onStack.incl(node)
    path.add(node)

    let deps = graph.getOrDefault(node, @[])
    for dep in deps:
      if dep in onStack:
        # Found a cycle - extract the cycle path.
        var cycleStart = path.len - 1
        while cycleStart > 0 and path[cycleStart - 1] != dep:
          dec cycleStart
        if cycleStart > 0:
          dec cycleStart
        var cycle = path[cycleStart .. ^1]
        cycle.add(dep)
        cycles.add(cycle)
      elif dep notin visited and dep in graph:
        dfs(dep, graph, cycles)

    discard path.pop()
    onStack.excl(node)

  var cycles: seq[seq[string]]
  for node in graph.keys:
    if node notin visited:
      dfs(node, graph, cycles)
  result = cycles

proc formatCycle(cycle: seq[string]): string =
  ## Format a cycle path as a readable string.
  result = cycle.join(" -> ")

proc detectAndLogCycles*(planPath: string): seq[seq[string]] =
  ## Build dependency graph and detect/log any cycles.
  let graph = buildDependencyGraph(planPath)
  let cycles = detectCycles(graph)
  for cycle in cycles:
    let cyclePath = formatCycle(cycle)
    let ticketId = cycle[0]
    logError(&"ticket {ticketId}: dependency cycle detected ({cyclePath})")
  result = cycles

proc scanForCycleBlockedTickets*(planPath: string) =
  ## Scan open and in-progress tickets for dependency cycles and log warnings.
  let graph = buildDependencyGraph(planPath)
  let cycles = detectCycles(graph)
  if cycles.len == 0:
    return

  var cycleTickets = initHashSet[string]()
  for cycle in cycles:
    for i in 0 ..< cycle.len - 1:
      cycleTickets.incl(cycle[i])

  for ticketId in cycleTickets:
    logWarn(&"ticket {ticketId}: permanently blocked by dependency cycle")
