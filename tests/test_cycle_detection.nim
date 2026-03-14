## Tests for dependency cycle detection.

import
  std/[sets, tables, unittest],
  scriptorium/cycle_detection

suite "dependency cycle detection":
  test "simple cycle: A depends on B, B depends on A":
    var graph: DependencyGraph
    graph["A"] = @["B"]
    graph["B"] = @["A"]

    let cycles = detectCycles(graph)
    check cycles.len > 0

    var foundCycle = false
    for cycle in cycles:
      let cycleSet = cycle.toHashSet()
      if "A" in cycleSet and "B" in cycleSet:
        foundCycle = true
        check cycle[0] == cycle[^1]
    check foundCycle

  test "multi-node cycle: A -> B -> C -> A":
    var graph: DependencyGraph
    graph["A"] = @["B"]
    graph["B"] = @["C"]
    graph["C"] = @["A"]

    let cycles = detectCycles(graph)
    check cycles.len > 0

    var foundCycle = false
    for cycle in cycles:
      let cycleSet = cycle.toHashSet()
      if "A" in cycleSet and "B" in cycleSet and "C" in cycleSet:
        foundCycle = true
        check cycle[0] == cycle[^1]
    check foundCycle

  test "no cycle: linear chain A -> B -> C":
    var graph: DependencyGraph
    graph["A"] = @["B"]
    graph["B"] = @["C"]
    graph["C"] = @[]

    let cycles = detectCycles(graph)
    check cycles.len == 0

  test "self-dependency: A depends on A":
    var graph: DependencyGraph
    graph["A"] = @["A"]

    let cycles = detectCycles(graph)
    check cycles.len > 0

    var foundSelfCycle = false
    for cycle in cycles:
      if "A" in cycle:
        foundSelfCycle = true
        check cycle[0] == cycle[^1]
    check foundSelfCycle

  test "mixed graph: some tickets in cycles, others not":
    var graph: DependencyGraph
    graph["A"] = @["B"]
    graph["B"] = @["A"]
    graph["C"] = @["D"]
    graph["D"] = @[]
    graph["E"] = @[]

    let cycles = detectCycles(graph)
    check cycles.len > 0

    var cycleTickets = initHashSet[string]()
    for cycle in cycles:
      for i in 0 ..< cycle.len - 1:
        cycleTickets.incl(cycle[i])

    check "A" in cycleTickets
    check "B" in cycleTickets
    check "C" notin cycleTickets
    check "D" notin cycleTickets
    check "E" notin cycleTickets

  test "empty graph has no cycles":
    var graph: DependencyGraph
    let cycles = detectCycles(graph)
    check cycles.len == 0

  test "dependency to non-existent ticket is not a cycle":
    var graph: DependencyGraph
    graph["A"] = @["B"]

    let cycles = detectCycles(graph)
    check cycles.len == 0
