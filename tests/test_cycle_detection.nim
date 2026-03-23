## Tests for dependency cycle detection.

import
  std/[sequtils, sets, tables, unittest],
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

suite "cycle auto-repair":
  test "repairCycles removes self-dependency edge":
    var graph: DependencyGraph
    graph["A"] = @["A", "B"]
    graph["B"] = @[]
    repairCycles(graph)
    check detectCycles(graph).len == 0
    let expectedA: seq[string] = @["B"]
    check graph["A"] == expectedA

  test "repairCycles breaks simple two-node cycle by removing edge from newest":
    var graph: DependencyGraph
    graph["0001"] = @["0002"]
    graph["0002"] = @["0001"]
    repairCycles(graph)
    check detectCycles(graph).len == 0
    # 0002 is newest, so its edge to 0001 should be removed
    let expected1: seq[string] = @["0002"]
    check graph["0001"] == expected1
    check graph["0002"].len == 0

  test "repairCycles breaks three-node cycle":
    var graph: DependencyGraph
    graph["0001"] = @["0002"]
    graph["0002"] = @["0003"]
    graph["0003"] = @["0001"]
    repairCycles(graph)
    check detectCycles(graph).len == 0

  test "repairCycles leaves non-cycle edges intact":
    var graph: DependencyGraph
    graph["0001"] = @["0002"]
    graph["0002"] = @["0001"]
    graph["0003"] = @["0004"]
    graph["0004"] = @[]
    repairCycles(graph)
    check detectCycles(graph).len == 0
    let expected3: seq[string] = @["0004"]
    check graph["0003"] == expected3

  test "repairCycles handles empty graph":
    var graph: DependencyGraph
    repairCycles(graph)
    check detectCycles(graph).len == 0
