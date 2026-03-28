import
  std/[os, osproc, strutils],
  scriptorium/[config, remote_sync]

proc run(dir: string, cmd: string) =
  ## Run a shell command in a directory. Raises on failure.
  let (output, rc) = execCmdEx(cmd, workingDir = dir)
  if rc != 0:
    raise newException(IOError, cmd & " failed: " & output.strip())

proc initBareRepo(path: string) =
  ## Create a bare git repository at the given path.
  createDir(path)
  run(path, "git init --bare")

proc initWorkRepo(path: string, defaultBranch: string = "master") =
  ## Create a working git repository with an initial commit.
  createDir(path)
  run(path, "git init -b " & defaultBranch)
  run(path, "git config user.email test@test.com")
  run(path, "git config user.name test")
  writeFile(path / "README.md", "init")
  run(path, "git add README.md")
  run(path, "git commit -m init")

proc addCommit(path: string, filename: string, content: string, message: string) =
  ## Add a file and commit in the given repo.
  writeFile(path / filename, content)
  run(path, "git add " & filename)
  run(path, "git commit -m " & quoteShell(message))

proc headSha(path: string): string =
  ## Return the HEAD commit SHA of a repo.
  let (output, rc) = execCmdEx("git rev-parse HEAD", workingDir = path)
  doAssert rc == 0
  result = output.strip()

proc testListRemotes() =
  ## Verify listRemotes returns configured remote names.
  let tmpDir = getTempDir() / "test_rs_list_remotes"
  removeDir(tmpDir)
  let workDir = tmpDir / "work"
  let bareDir = tmpDir / "bare"
  initBareRepo(bareDir)
  initWorkRepo(workDir)
  run(workDir, "git remote add origin " & bareDir)
  run(workDir, "git remote add gitea " & bareDir)

  let remotes = listRemotes(workDir)
  doAssert "origin" in remotes
  doAssert "gitea" in remotes
  doAssert remotes.len == 2

  removeDir(tmpDir)
  echo "[OK] listRemotes returns configured remote names"

proc testFetchAllRemotes() =
  ## Verify fetchAllRemotes fetches from all configured remotes.
  let tmpDir = getTempDir() / "test_rs_fetch_all"
  removeDir(tmpDir)
  let workDir = tmpDir / "work"
  let bareOrigin = tmpDir / "origin.git"
  let bareGitea = tmpDir / "gitea.git"
  initBareRepo(bareOrigin)
  initBareRepo(bareGitea)
  initWorkRepo(workDir)
  run(workDir, "git remote add origin " & bareOrigin)
  run(workDir, "git remote add gitea " & bareGitea)
  run(workDir, "git push origin master")
  run(workDir, "git push gitea master")

  let fetchResult = fetchAllRemotes(workDir, @["origin", "gitea"])
  doAssert fetchResult.fetched == 2
  doAssert fetchResult.failures == 0

  removeDir(tmpDir)
  echo "[OK] fetchAllRemotes fetches from all remotes"

proc testFastForwardMerge() =
  ## Verify mergeFromPrimary fast-forwards when primary is ahead.
  let tmpDir = getTempDir() / "test_rs_ff_merge"
  removeDir(tmpDir)
  let workDir = tmpDir / "work"
  let bareGitea = tmpDir / "gitea.git"
  let pusherDir = tmpDir / "pusher"
  initBareRepo(bareGitea)
  initWorkRepo(workDir)
  run(workDir, "git remote add gitea " & bareGitea)
  run(workDir, "git push gitea master")

  # Clone and push a new commit to gitea.
  run(tmpDir, "git clone " & bareGitea & " pusher")
  run(pusherDir, "git config user.email test@test.com")
  run(pusherDir, "git config user.name test")
  addCommit(pusherDir, "new.txt", "hello", "add new file")
  run(pusherDir, "git push origin master")

  # Fetch and merge in working repo.
  discard fetchAllRemotes(workDir, @["gitea"])
  # Set up origin/HEAD so resolveDefaultBranch works.
  run(workDir, "git remote set-head gitea master")
  let mergeResult = mergeFromPrimary(workDir, "gitea", "master")
  doAssert mergeResult == smrFastForward
  doAssert fileExists(workDir / "new.txt")

  removeDir(tmpDir)
  echo "[OK] mergeFromPrimary fast-forwards when primary is ahead"

proc testUpToDate() =
  ## Verify mergeFromPrimary returns smrUpToDate when already synced.
  let tmpDir = getTempDir() / "test_rs_up_to_date"
  removeDir(tmpDir)
  let workDir = tmpDir / "work"
  let bareGitea = tmpDir / "gitea.git"
  initBareRepo(bareGitea)
  initWorkRepo(workDir)
  run(workDir, "git remote add gitea " & bareGitea)
  run(workDir, "git push gitea master")
  discard fetchAllRemotes(workDir, @["gitea"])

  let mergeResult = mergeFromPrimary(workDir, "gitea", "master")
  doAssert mergeResult == smrUpToDate

  removeDir(tmpDir)
  echo "[OK] mergeFromPrimary returns smrUpToDate when synced"

proc testDivergedMergeGiteaWins() =
  ## Verify that when both local and gitea diverge, gitea's version wins on conflicts.
  let tmpDir = getTempDir() / "test_rs_diverge"
  removeDir(tmpDir)
  let workDir = tmpDir / "work"
  let bareGitea = tmpDir / "gitea.git"
  let pusherDir = tmpDir / "pusher"
  initBareRepo(bareGitea)
  initWorkRepo(workDir)
  run(workDir, "git remote add gitea " & bareGitea)
  run(workDir, "git push gitea master")

  # Clone gitea and push a conflicting change.
  run(tmpDir, "git clone " & bareGitea & " pusher")
  run(pusherDir, "git config user.email test@test.com")
  run(pusherDir, "git config user.name test")
  addCommit(pusherDir, "conflict.txt", "gitea wins", "gitea change")
  run(pusherDir, "git push origin master")

  # Make a conflicting local change.
  addCommit(workDir, "conflict.txt", "local loses", "local change")

  # Fetch and merge — gitea should win.
  discard fetchAllRemotes(workDir, @["gitea"])
  let mergeResult = mergeFromPrimary(workDir, "gitea", "master")
  doAssert mergeResult == smrMerged
  let content = readFile(workDir / "conflict.txt")
  doAssert content.strip() == "gitea wins"

  removeDir(tmpDir)
  echo "[OK] diverged merge resolves with gitea winning"

proc testPushToAllRemotes() =
  ## Verify pushToAllRemotes pushes to all configured remotes.
  let tmpDir = getTempDir() / "test_rs_push_all"
  removeDir(tmpDir)
  let workDir = tmpDir / "work"
  let bareOrigin = tmpDir / "origin.git"
  let bareGitea = tmpDir / "gitea.git"
  initBareRepo(bareOrigin)
  initBareRepo(bareGitea)
  initWorkRepo(workDir)
  run(workDir, "git remote add origin " & bareOrigin)
  run(workDir, "git remote add gitea " & bareGitea)

  let cfg = RemoteSyncConfig(
    enabled: true,
    primaryRemote: "gitea",
    remotes: @["origin", "gitea"],
    syncIntervalSeconds: 0,
  )
  pushToAllRemotes(workDir, cfg)

  # Verify both bare repos have the commit.
  let localSha = headSha(workDir)
  let (originSha, _) = execCmdEx("git rev-parse master", workingDir = bareOrigin)
  let (giteaSha, _) = execCmdEx("git rev-parse master", workingDir = bareGitea)
  doAssert originSha.strip() == localSha
  doAssert giteaSha.strip() == localSha

  removeDir(tmpDir)
  echo "[OK] pushToAllRemotes pushes to all remotes"

proc testSyncRemotesFull() =
  ## Verify a full sync cycle: fetch, merge, push across two remotes.
  let tmpDir = getTempDir() / "test_rs_full_sync"
  removeDir(tmpDir)
  let workDir = tmpDir / "work"
  let bareOrigin = tmpDir / "origin.git"
  let bareGitea = tmpDir / "gitea.git"
  let pusherDir = tmpDir / "pusher"
  initBareRepo(bareOrigin)
  initBareRepo(bareGitea)
  initWorkRepo(workDir)
  run(workDir, "git remote add origin " & bareOrigin)
  run(workDir, "git remote add gitea " & bareGitea)
  run(workDir, "git push origin master")
  run(workDir, "git push gitea master")
  # Set remote HEAD so resolveDefaultBranch works.
  run(workDir, "git remote set-head origin master")

  # Push a new commit to gitea from a separate clone.
  run(tmpDir, "git clone " & bareGitea & " pusher")
  run(pusherDir, "git config user.email test@test.com")
  run(pusherDir, "git config user.name test")
  addCommit(pusherDir, "synced.txt", "from gitea", "gitea commit")
  run(pusherDir, "git push origin master")

  let cfg = RemoteSyncConfig(
    enabled: true,
    primaryRemote: "gitea",
    remotes: @["origin", "gitea"],
    syncIntervalSeconds: 0,
  )
  let syncResult = syncRemotes(workDir, cfg)
  doAssert syncResult.fetchedRemotes == 2
  doAssert syncResult.fetchFailures == 0
  doAssert syncResult.mergeResult == smrFastForward
  doAssert syncResult.pushedRemotes == 2
  doAssert syncResult.pushFailures == 0

  # Verify origin also got the commit from gitea.
  let localSha = headSha(workDir)
  let (originSha, _) = execCmdEx("git rev-parse master", workingDir = bareOrigin)
  doAssert originSha.strip() == localSha

  removeDir(tmpDir)
  echo "[OK] full sync cycle works end-to-end"

proc testRemoteSyncConfigDefaults() =
  ## Verify RemoteSyncConfig defaults in the config system.
  let cfg = defaultConfig()
  doAssert cfg.remoteSync.enabled == false
  doAssert cfg.remoteSync.primaryRemote == "gitea"
  doAssert cfg.remoteSync.remotes.len == 0
  doAssert cfg.remoteSync.syncIntervalSeconds == 60
  echo "[OK] RemoteSyncConfig defaults are correct"

proc testRemoteSyncConfigLoading() =
  ## Verify RemoteSyncConfig is loaded from scriptorium.json.
  let tmpDir = getTempDir() / "test_rs_config_load"
  removeDir(tmpDir)
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"remoteSync": {"enabled": true, "primaryRemote": "gitea", "remotes": ["origin", "gitea"], "syncIntervalSeconds": 30}}"""
  writeFile(tmpDir / "scriptorium.json", json)

  let cfg = loadConfig(tmpDir)
  doAssert cfg.remoteSync.enabled == true
  doAssert cfg.remoteSync.primaryRemote == "gitea"
  doAssert cfg.remoteSync.remotes == @["origin", "gitea"]
  doAssert cfg.remoteSync.syncIntervalSeconds == 30
  echo "[OK] RemoteSyncConfig is loaded from JSON"

when isMainModule:
  testRemoteSyncConfigDefaults()
  testRemoteSyncConfigLoading()
  testListRemotes()
  testFetchAllRemotes()
  testUpToDate()
  testFastForwardMerge()
  testDivergedMergeGiteaWins()
  testPushToAllRemotes()
  testSyncRemotesFull()
