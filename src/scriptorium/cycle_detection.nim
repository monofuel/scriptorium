import
  std/[os, sets, strformat, strutils, tables],
  ./[logging, shared_state, ticket_metadata]

type
  DependencyGraph* = Table[string, seq[string]]

proc buildDependencyGraph*(planPath: string): DependencyGraph =
  ## Build a directed graph from open and in-progress tickets using Depends fields.
  ## Self-references are silently stripped.
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
      var filtered: seq[string]
      for dep in deps:
        if dep != ticketId:
          filtered.add(dep)
        else:
          logWarn(&"ticket {ticketId}: stripped self-reference from dependencies")
      result[ticketId] = filtered

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

proc repairCycles*(graph: var DependencyGraph) =
  ## Detect cycles and break them by removing the edge from the highest-numbered
  ## (newest) ticket in each cycle. Repeats until no cycles remain.
  while true:
    let cycles = detectCycles(graph)
    if cycles.len == 0:
      break
    for cycle in cycles:
      # Find the newest ticket in the cycle (highest ID string).
      let members = cycle[0 ..< cycle.len - 1]
      if members.len == 0:
        continue
      var newest = members[0]
      for member in members[1 .. ^1]:
        if member > newest:
          newest = member
      # Remove all edges from `newest` that point to other cycle members.
      if newest in graph:
        var kept: seq[string]
        let cycleSet = members.toHashSet()
        for dep in graph[newest]:
          if dep notin cycleSet:
            kept.add(dep)
          else:
            logWarn(&"ticket {newest}: auto-repaired dependency cycle, removed edge to {dep}")
        graph[newest] = kept

proc buildRepairedDependencyGraph*(planPath: string): DependencyGraph =
  ## Build a dependency graph with self-references stripped and cycles auto-repaired.
  result = buildDependencyGraph(planPath)
  repairCycles(result)

proc scanForCycleBlockedTickets*(planPath: string) =
  ## Scan open and in-progress tickets for dependency cycles and log repairs.
  var graph = buildDependencyGraph(planPath)
  repairCycles(graph)
