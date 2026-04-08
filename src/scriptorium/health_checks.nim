import
  std/[algorithm, json, os, sequtils, strformat, tables, times],
  ./[git_ops, logging, shared_state]

const
  HealthCacheDir* = "health"
  HealthCacheFileName* = "cache.json"
  HealthCacheRelPath* = "health/cache.json"
  HealthCacheCommitMessage* = "scriptorium: update health cache"
  MaxHealthCacheEntries* = 100

type
  MasterHealthState* = object
    head*: string
    healthy*: bool
    initialized*: bool
    lastHealthLogged*: bool
    testOutput*: string

proc pruneHealthCache*(cache: Table[string, HealthCacheEntry], maxEntries: int): Table[string, HealthCacheEntry] =
  ## Return a pruned copy of the cache keeping only the most recent maxEntries by timestamp.
  if cache.len <= maxEntries:
    return cache
  var entries = toSeq(cache.pairs)
  entries.sort(proc(a, b: (string, HealthCacheEntry)): int =
    cmp(b[1].timestamp, a[1].timestamp)
  )
  result = initTable[string, HealthCacheEntry]()
  for i in 0 ..< maxEntries:
    result[entries[i][0]] = entries[i][1]

proc readHealthCache*(planPath: string): Table[string, HealthCacheEntry] =
  ## Read health/cache.json from a plan worktree path and return the cache table.
  ## Missing fields get safe defaults; malformed entries are skipped; invalid
  ## JSON returns an empty table.
  let cachePath = planPath / HealthCacheRelPath
  if not fileExists(cachePath):
    return initTable[string, HealthCacheEntry]()
  let raw = readFile(cachePath)
  var rootNode: JsonNode
  try:
    rootNode = parseJson(raw)
  except JsonParsingError:
    logWarn("health cache: failed to parse JSON, returning empty cache")
    return initTable[string, HealthCacheEntry]()
  for commitHash, entryNode in rootNode.pairs:
    try:
      let entry = HealthCacheEntry(
        healthy: entryNode{"healthy"}.getBool(),
        timestamp: entryNode{"timestamp"}.getStr(),
        test_exit_code: entryNode{"test_exit_code"}.getInt(),
        integration_test_exit_code: entryNode{"integration_test_exit_code"}.getInt(),
        test_wall_seconds: entryNode{"test_wall_seconds"}.getInt(),
        integration_test_wall_seconds: entryNode{"integration_test_wall_seconds"}.getInt(),
      )
      result[commitHash] = entry
    except CatchableError:
      let msg = getCurrentExceptionMsg()
      logWarn(&"health cache: skipping malformed entry {commitHash}: {msg}")

proc writeHealthCache*(planPath: string, cache: Table[string, HealthCacheEntry]) =
  ## Write the health cache table to health/cache.json in a plan worktree path.
  let cacheDir = planPath / HealthCacheDir
  if not dirExists(cacheDir):
    createDir(cacheDir)
  var rootNode = newJObject()
  for commitHash, entry in cache.pairs:
    var entryNode = newJObject()
    entryNode["healthy"] = newJBool(entry.healthy)
    entryNode["timestamp"] = newJString(entry.timestamp)
    entryNode["test_exit_code"] = newJInt(entry.test_exit_code)
    entryNode["integration_test_exit_code"] = newJInt(entry.integration_test_exit_code)
    entryNode["test_wall_seconds"] = newJInt(entry.test_wall_seconds)
    entryNode["integration_test_wall_seconds"] = newJInt(entry.integration_test_wall_seconds)
    rootNode[commitHash] = entryNode
  atomicWriteFile(planPath / HealthCacheRelPath, $rootNode)

proc commitHealthCache*(planPath: string) =
  ## Stage and commit health/cache.json on the plan branch.
  gitRun(planPath, "add", HealthCacheRelPath)
  gitRun(planPath, "commit", "-m", HealthCacheCommitMessage)
