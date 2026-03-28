import
  std/[json, os, strformat, tables, times],
  ./[git_ops, logging, shared_state]

const
  HealthCacheDir* = "health"
  HealthCacheFileName* = "cache.json"
  HealthCacheRelPath* = "health/cache.json"
  HealthCacheCommitMessage* = "scriptorium: update health cache"

type
  MasterHealthState* = object
    head*: string
    healthy*: bool
    initialized*: bool
    lastHealthLogged*: bool
    testOutput*: string

proc readHealthCache*(planPath: string): Table[string, HealthCacheEntry] =
  ## Read health/cache.json from a plan worktree path and return the cache table.
  let cachePath = planPath / HealthCacheRelPath
  if not fileExists(cachePath):
    return initTable[string, HealthCacheEntry]()
  let raw = readFile(cachePath)
  let rootNode = parseJson(raw)
  for commitHash, entryNode in rootNode.pairs:
    var entry = HealthCacheEntry(
      healthy: entryNode["healthy"].getBool(),
      timestamp: entryNode["timestamp"].getStr(),
      test_exit_code: entryNode["test_exit_code"].getInt(),
      integration_test_exit_code: entryNode["integration_test_exit_code"].getInt(),
      test_wall_seconds: entryNode["test_wall_seconds"].getInt(),
      integration_test_wall_seconds: entryNode["integration_test_wall_seconds"].getInt(),
    )
    result[commitHash] = entry

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
  writeFile(planPath / HealthCacheRelPath, $rootNode)

proc commitHealthCache*(planPath: string) =
  ## Stage and commit health/cache.json on the plan branch.
  gitRun(planPath, "add", HealthCacheRelPath)
  gitRun(planPath, "commit", "-m", HealthCacheCommitMessage)
