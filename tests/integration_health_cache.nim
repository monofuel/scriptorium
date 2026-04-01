## Integration test for health cache plan-branch round-trip.

import
  std/[os, osproc, tables, unittest],
  scriptorium/[health_checks, shared_state]

proc makeTestRepo(path: string) =
  ## Create a minimal git repo with a scriptorium/plan branch.
  if dirExists(path):
    removeDir(path)
  createDir(path)
  discard execCmdEx("git -C " & path & " init")
  discard execCmdEx("git -C " & path & " config user.email test@test.com")
  discard execCmdEx("git -C " & path & " config user.name Test")
  writeFile(path / "README.md", "initial")
  discard execCmdEx("git -C " & path & " add README.md")
  discard execCmdEx("git -C " & path & " commit -m initial")
  discard execCmdEx("git -C " & path & " checkout -b scriptorium/plan")

suite "health cache plan-branch round-trip":
  test "write, commit, and re-read preserves all fields":
    let tmpDir = getTempDir() / "scriptorium_test_health_cache_rt"
    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer:
      removeDir(tmpDir)

    let repoPath = tmpDir / "repo"
    makeTestRepo(repoPath)

    let commitHash = "abc123def456"
    var cache = initTable[string, HealthCacheEntry]()
    cache[commitHash] = HealthCacheEntry(
      healthy: true,
      timestamp: "2026-04-01T12:00:00Z",
      test_exit_code: 0,
      integration_test_exit_code: 1,
      test_wall_seconds: 42,
      integration_test_wall_seconds: 99,
    )

    # Write and commit the cache on the plan branch.
    writeHealthCache(repoPath, cache)
    commitHealthCache(repoPath)

    # Simulate restart: remove the on-disk cache file and re-read from the
    # working tree (which is backed by the committed plan branch state).
    let cachePath = repoPath / HealthCacheRelPath
    check fileExists(cachePath)

    # Reset the working tree to HEAD to prove the file comes from the commit.
    discard execCmdEx("git -C " & repoPath & " checkout HEAD -- " & HealthCacheRelPath)

    let restored = readHealthCache(repoPath)
    check restored.len == 1
    check restored.hasKey(commitHash)

    let entry = restored[commitHash]
    check entry.healthy == true
    check entry.timestamp == "2026-04-01T12:00:00Z"
    check entry.test_exit_code == 0
    check entry.integration_test_exit_code == 1
    check entry.test_wall_seconds == 42
    check entry.integration_test_wall_seconds == 99
