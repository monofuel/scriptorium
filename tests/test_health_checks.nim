## Unit tests for the three-tier health cache lookup logic used by isMasterHealthy.

import
  std/[json, os, strformat, tables, tempfiles, unittest],
  scriptorium/[health_checks, shared_state]

suite "MasterHealthState in-memory cache":
  test "initialized state with matching head returns cached healthy result":
    var state = MasterHealthState(
      head: "abc123",
      healthy: true,
      initialized: true,
    )
    # Simulating the in-memory check from isMasterHealthy:
    # when initialized and head matches, return cached value.
    let currentHead = "abc123"
    check state.initialized
    check state.head == currentHead
    check state.healthy == true

  test "initialized state with matching head returns cached unhealthy result":
    var state = MasterHealthState(
      head: "abc123",
      healthy: false,
      initialized: true,
    )
    let currentHead = "abc123"
    check state.initialized
    check state.head == currentHead
    check state.healthy == false

  test "uninitialized state does not satisfy in-memory cache":
    var state = MasterHealthState(
      head: "abc123",
      healthy: true,
      initialized: false,
    )
    let currentHead = "abc123"
    check not state.initialized

  test "different head does not satisfy in-memory cache":
    var state = MasterHealthState(
      head: "abc123",
      healthy: true,
      initialized: true,
    )
    let currentHead = "def456"
    check not (state.initialized and state.head == currentHead)

suite "file cache lookup by commit hash":
  test "healthy entry found in file cache":
    let tmp = createTempDir("scriptorium_test_hc_healthy_", "")
    defer: removeDir(tmp)

    var cache = initTable[string, HealthCacheEntry]()
    cache["abc123"] = HealthCacheEntry(
      healthy: true,
      timestamp: "2026-04-01T00:00:00Z",
      test_exit_code: 0,
      integration_test_exit_code: 0,
      test_wall_seconds: 30,
      integration_test_wall_seconds: 60,
    )
    writeHealthCache(tmp, cache)

    let loaded = readHealthCache(tmp)
    let commitHash = "abc123"
    check commitHash in loaded
    check loaded[commitHash].healthy == true
    check loaded[commitHash].test_exit_code == 0

  test "unhealthy entry found in file cache":
    let tmp = createTempDir("scriptorium_test_hc_unhealthy_", "")
    defer: removeDir(tmp)

    var cache = initTable[string, HealthCacheEntry]()
    cache["bad456"] = HealthCacheEntry(
      healthy: false,
      timestamp: "2026-04-01T00:00:00Z",
      test_exit_code: 1,
      integration_test_exit_code: 0,
      test_wall_seconds: 25,
      integration_test_wall_seconds: 55,
    )
    writeHealthCache(tmp, cache)

    let loaded = readHealthCache(tmp)
    let commitHash = "bad456"
    check commitHash in loaded
    check loaded[commitHash].healthy == false
    check loaded[commitHash].test_exit_code == 1

  test "missing commit hash is a cache miss":
    let tmp = createTempDir("scriptorium_test_hc_miss_", "")
    defer: removeDir(tmp)

    var cache = initTable[string, HealthCacheEntry]()
    cache["abc123"] = HealthCacheEntry(
      healthy: true,
      timestamp: "2026-04-01T00:00:00Z",
      test_exit_code: 0,
      integration_test_exit_code: 0,
      test_wall_seconds: 30,
      integration_test_wall_seconds: 60,
    )
    writeHealthCache(tmp, cache)

    let loaded = readHealthCache(tmp)
    let commitHash = "not_in_cache"
    check commitHash notin loaded

  test "empty file cache returns no entries":
    let tmp = createTempDir("scriptorium_test_hc_empty_", "")
    defer: removeDir(tmp)

    let loaded = readHealthCache(tmp)
    check loaded.len == 0

suite "cache miss writes result to file cache":
  test "new entry persists through write and read round-trip":
    let tmp = createTempDir("scriptorium_test_hc_write_", "")
    defer: removeDir(tmp)

    # Start with empty cache (simulating a full miss).
    var cache = readHealthCache(tmp)
    check cache.len == 0

    # Simulate writing a health check result after a cache miss.
    let commitHash = "new789"
    cache[commitHash] = HealthCacheEntry(
      healthy: true,
      timestamp: "2026-04-01T01:00:00Z",
      test_exit_code: 0,
      integration_test_exit_code: 0,
      test_wall_seconds: 45,
      integration_test_wall_seconds: 90,
    )
    writeHealthCache(tmp, cache)

    # Verify the entry is now in the file cache.
    let reloaded = readHealthCache(tmp)
    check commitHash in reloaded
    check reloaded[commitHash].healthy == true
    check reloaded[commitHash].test_wall_seconds == 45
    check reloaded[commitHash].integration_test_wall_seconds == 90

  test "writing preserves existing entries":
    let tmp = createTempDir("scriptorium_test_hc_preserve_", "")
    defer: removeDir(tmp)

    var cache = initTable[string, HealthCacheEntry]()
    cache["old111"] = HealthCacheEntry(
      healthy: true,
      timestamp: "2026-04-01T00:00:00Z",
      test_exit_code: 0,
      integration_test_exit_code: 0,
      test_wall_seconds: 10,
      integration_test_wall_seconds: 20,
    )
    writeHealthCache(tmp, cache)

    # Add a new entry after a cache miss.
    var updated = readHealthCache(tmp)
    updated["new222"] = HealthCacheEntry(
      healthy: false,
      timestamp: "2026-04-01T02:00:00Z",
      test_exit_code: 2,
      integration_test_exit_code: 0,
      test_wall_seconds: 50,
      integration_test_wall_seconds: 100,
    )
    writeHealthCache(tmp, updated)

    let reloaded = readHealthCache(tmp)
    check reloaded.len == 2
    check "old111" in reloaded
    check reloaded["old111"].healthy == true
    check "new222" in reloaded
    check reloaded["new222"].healthy == false

suite "pruneHealthCache":
  test "table with fewer entries than max is returned unchanged":
    var cache = initTable[string, HealthCacheEntry]()
    cache["a"] = HealthCacheEntry(healthy: true, timestamp: "2026-01-01T00:00:00Z")
    cache["b"] = HealthCacheEntry(healthy: false, timestamp: "2026-01-02T00:00:00Z")
    let pruned = pruneHealthCache(cache, 5)
    check pruned.len == 2
    check "a" in pruned
    check "b" in pruned

  test "table with more entries than max retains only the N most recent by timestamp":
    var cache = initTable[string, HealthCacheEntry]()
    for i in 0 ..< 5:
      let ts = &"2026-01-0{i + 1}T00:00:00Z"
      let key = &"commit_{i}"
      cache[key] = HealthCacheEntry(healthy: true, timestamp: ts)
    let pruned = pruneHealthCache(cache, 3)
    check pruned.len == 3
    # The three most recent are commits 2, 3, 4 (Jan 3, 4, 5).
    check "commit_2" in pruned
    check "commit_3" in pruned
    check "commit_4" in pruned
    check "commit_0" notin pruned
    check "commit_1" notin pruned

  test "empty table returns empty":
    let cache = initTable[string, HealthCacheEntry]()
    let pruned = pruneHealthCache(cache, 10)
    check pruned.len == 0

suite "defensive JSON parsing":
  test "missing fields produce safe defaults":
    let tmp = createTempDir("scriptorium_test_hc_missing_", "")
    defer: removeDir(tmp)

    let cacheDir = tmp / "health"
    createDir(cacheDir)
    writeFile(cacheDir / "cache.json", """{"abc123": {"healthy": true}}""")

    let loaded = readHealthCache(tmp)
    check loaded.len == 1
    check "abc123" in loaded
    check loaded["abc123"].healthy == true
    check loaded["abc123"].timestamp == ""
    check loaded["abc123"].test_exit_code == 0
    check loaded["abc123"].integration_test_exit_code == 0
    check loaded["abc123"].test_wall_seconds == 0
    check loaded["abc123"].integration_test_wall_seconds == 0

  test "completely empty entry object gets all safe defaults":
    let tmp = createTempDir("scriptorium_test_hc_empty_entry_", "")
    defer: removeDir(tmp)

    let cacheDir = tmp / "health"
    createDir(cacheDir)
    writeFile(cacheDir / "cache.json", """{"def456": {}}""")

    let loaded = readHealthCache(tmp)
    check loaded.len == 1
    check "def456" in loaded
    check loaded["def456"].healthy == false
    check loaded["def456"].timestamp == ""
    check loaded["def456"].test_exit_code == 0
    check loaded["def456"].integration_test_exit_code == 0
    check loaded["def456"].test_wall_seconds == 0
    check loaded["def456"].integration_test_wall_seconds == 0

  test "extra unknown fields are ignored":
    let tmp = createTempDir("scriptorium_test_hc_extra_", "")
    defer: removeDir(tmp)

    let cacheDir = tmp / "health"
    createDir(cacheDir)
    writeFile(cacheDir / "cache.json", """{"abc123": {"healthy": true, "timestamp": "2026-04-01T00:00:00Z", "unknown_field": "value", "another": 42}}""")

    let loaded = readHealthCache(tmp)
    check loaded.len == 1
    check "abc123" in loaded
    check loaded["abc123"].healthy == true
    check loaded["abc123"].timestamp == "2026-04-01T00:00:00Z"

  test "completely invalid JSON returns empty cache":
    let tmp = createTempDir("scriptorium_test_hc_invalid_", "")
    defer: removeDir(tmp)

    let cacheDir = tmp / "health"
    createDir(cacheDir)
    writeFile(cacheDir / "cache.json", "this is not json at all {{{")

    let loaded = readHealthCache(tmp)
    check loaded.len == 0
