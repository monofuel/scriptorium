## Unit tests for shared state management, health cache, and token budget tracking.

import
  std/[os, tables, tempfiles, times, unittest],
  scriptorium/[agent_pool, health_checks, shared_state]

suite "cleanupTicketTimings":
  setup:
    ticketStartTimes.clear()
    ticketAttemptCounts.clear()
    ticketCodingWalls.clear()
    ticketTestWalls.clear()
    ticketModels.clear()
    ticketOutputBytes.clear()

  test "removes all state for a ticket":
    let ticketId = "0046"
    ticketStartTimes[ticketId] = epochTime()
    ticketAttemptCounts[ticketId] = 1
    ticketCodingWalls[ticketId] = 10.0
    ticketTestWalls[ticketId] = 5.0
    ticketModels[ticketId] = "test-model"
    ticketOutputBytes[ticketId] = 100

    cleanupTicketTimings(ticketId)
    check ticketId notin ticketStartTimes
    check ticketId notin ticketAttemptCounts
    check ticketId notin ticketCodingWalls
    check ticketId notin ticketTestWalls
    check ticketId notin ticketModels
    check ticketId notin ticketOutputBytes

suite "health cache persistence":
  test "readHealthCache returns empty table when file does not exist":
    let tmp = createTempDir("scriptorium_test_health_cache_empty_", "")
    defer: removeDir(tmp)

    let cache = readHealthCache(tmp)
    check cache.len == 0

  test "writeHealthCache creates directory and file then readHealthCache round-trips":
    let tmp = createTempDir("scriptorium_test_health_cache_roundtrip_", "")
    defer: removeDir(tmp)

    var cache = initTable[string, HealthCacheEntry]()
    cache["abc123"] = HealthCacheEntry(
      healthy: true,
      timestamp: "2026-03-13T12:00:00Z",
      test_exit_code: 0,
      integration_test_exit_code: 0,
      test_wall_seconds: 45,
      integration_test_wall_seconds: 120,
    )
    cache["def456"] = HealthCacheEntry(
      healthy: false,
      timestamp: "2026-03-13T13:00:00Z",
      test_exit_code: 1,
      integration_test_exit_code: 0,
      test_wall_seconds: 10,
      integration_test_wall_seconds: 0,
    )

    writeHealthCache(tmp, cache)

    check fileExists(tmp / "health" / "cache.json")

    let loaded = readHealthCache(tmp)
    check loaded.len == 2
    check loaded["abc123"].healthy == true
    check loaded["abc123"].test_exit_code == 0
    check loaded["abc123"].integration_test_exit_code == 0
    check loaded["abc123"].test_wall_seconds == 45
    check loaded["abc123"].integration_test_wall_seconds == 120
    check loaded["def456"].healthy == false
    check loaded["def456"].test_exit_code == 1

  test "readHealthCache parses JSON with correct field types":
    let tmp = createTempDir("scriptorium_test_health_cache_parse_", "")
    createDir(tmp / "health")
    defer: removeDir(tmp)

    let jsonContent = """{"commit1": {"healthy": true, "timestamp": "2026-03-13T12:00:00Z", "test_exit_code": 0, "integration_test_exit_code": 0, "test_wall_seconds": 30, "integration_test_wall_seconds": 60}}"""
    writeFile(tmp / "health" / "cache.json", jsonContent)

    let cache = readHealthCache(tmp)
    check cache.len == 1
    check "commit1" in cache
    check cache["commit1"].healthy == true
    check cache["commit1"].timestamp == "2026-03-13T12:00:00Z"
    check cache["commit1"].test_wall_seconds == 30
    check cache["commit1"].integration_test_wall_seconds == 60

  test "writeHealthCache overwrites existing cache":
    let tmp = createTempDir("scriptorium_test_health_cache_overwrite_", "")
    defer: removeDir(tmp)

    var cache1 = initTable[string, HealthCacheEntry]()
    cache1["abc"] = HealthCacheEntry(healthy: true, timestamp: "t1", test_exit_code: 0, integration_test_exit_code: 0, test_wall_seconds: 1, integration_test_wall_seconds: 2)
    writeHealthCache(tmp, cache1)

    var cache2 = initTable[string, HealthCacheEntry]()
    cache2["abc"] = HealthCacheEntry(healthy: true, timestamp: "t1", test_exit_code: 0, integration_test_exit_code: 0, test_wall_seconds: 1, integration_test_wall_seconds: 2)
    cache2["def"] = HealthCacheEntry(healthy: false, timestamp: "t2", test_exit_code: 1, integration_test_exit_code: 0, test_wall_seconds: 5, integration_test_wall_seconds: 0)
    writeHealthCache(tmp, cache2)

    let loaded = readHealthCache(tmp)
    check loaded.len == 2
    check "abc" in loaded
    check "def" in loaded

suite "agent slot types":
  test "AgentSlot stores ticket metadata with role":
    let slot = AgentSlot(
      role: arCoder,
      ticketId: "0042",
      branch: "scriptorium/ticket-0042",
      worktree: "/tmp/worktrees/0042",
      startTime: 1234567890.0,
    )
    check slot.role == arCoder
    check slot.ticketId == "0042"
    check slot.branch == "scriptorium/ticket-0042"
    check slot.worktree == "/tmp/worktrees/0042"
    check slot.startTime == 1234567890.0

  test "AgentSlot manager uses areaId with empty branch and worktree":
    let slot = AgentSlot(
      role: arManager,
      areaId: "backend-api",
      startTime: 1234567890.0,
    )
    check slot.role == arManager
    check slot.areaId == "backend-api"
    check slot.branch == ""
    check slot.worktree == ""

  test "runningAgentCount returns zero initially":
    check runningAgentCount() == 0

  test "emptySlotCount returns maxAgents when no agents running":
    check emptySlotCount(4) == 4

suite "output budget tracking":
  setup:
    ticketOutputBytes.clear()
    resetSessionStats()

  test "getSessionOutputBytes sums all ticket values":
    ticketOutputBytes["0001"] = 1000
    recordOutputBytes(1000)
    ticketOutputBytes["0002"] = 2000
    recordOutputBytes(2000)
    ticketOutputBytes["0003"] = 3000
    recordOutputBytes(3000)
    check getSessionOutputBytes() == 6000

  test "getSessionOutputBytes returns 0 when empty":
    check getSessionOutputBytes() == 0

  test "isOutputBudgetExceeded returns false when tokenBudgetMB is 0":
    ticketOutputBytes["0001"] = 100 * 1024 * 1024
    recordOutputBytes(100 * 1024 * 1024)
    check isOutputBudgetExceeded(0) == false

  test "isOutputBudgetExceeded returns false when tokenBudgetMB is negative":
    ticketOutputBytes["0001"] = 100 * 1024 * 1024
    recordOutputBytes(100 * 1024 * 1024)
    check isOutputBudgetExceeded(-1) == false

  test "isOutputBudgetExceeded returns true when budget exceeded":
    ticketOutputBytes["0001"] = 5 * 1024 * 1024
    recordOutputBytes(5 * 1024 * 1024)
    ticketOutputBytes["0002"] = 6 * 1024 * 1024
    recordOutputBytes(6 * 1024 * 1024)
    check isOutputBudgetExceeded(10) == true

  test "isOutputBudgetExceeded returns false when under budget":
    ticketOutputBytes["0001"] = 2 * 1024 * 1024
    recordOutputBytes(2 * 1024 * 1024)
    ticketOutputBytes["0002"] = 3 * 1024 * 1024
    recordOutputBytes(3 * 1024 * 1024)
    check isOutputBudgetExceeded(10) == false

  test "running agents not interrupted when budget exceeded":
    ## Verify that ticketOutputBytes entries remain intact when budget is exceeded.
    ticketOutputBytes["0001"] = 5 * 1024 * 1024
    recordOutputBytes(5 * 1024 * 1024)
    ticketOutputBytes["0002"] = 6 * 1024 * 1024
    recordOutputBytes(6 * 1024 * 1024)
    let exceeded = isOutputBudgetExceeded(10)
    check exceeded == true
    # Existing entries are not cleared or modified.
    check ticketOutputBytes["0001"] == 5 * 1024 * 1024
    check ticketOutputBytes["0002"] == 6 * 1024 * 1024

  test "completed tickets do not replenish the session budget":
    ticketOutputBytes["done"] = 1024
    recordOutputBytes(1024)
    cleanupTicketTimings("done")
    check getSessionOutputBytes() == 1024
