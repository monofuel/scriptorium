import
  std/[locks, os, osproc, streams, strformat, strutils, times],
  ./logging

const
  GitCommandTimeoutMs* = 60_000
  GitLockMaxAgeSeconds = 300
  GitLockFiles = [".git/packed-refs.lock", ".git/index.lock"]
  PlanBranch* = "scriptorium/plan"
  ManagedStateDirName* = ".scriptorium"
  ManagedWorktreeDirName* = "worktrees"
  ManagedPlanWorktreeName* {.deprecated: "use PlanCaller* constants instead".} = "plan"
  ManagedMasterWorktreeName* = "master"
  PlanCallerCli* = "plan-cli"
  PlanCallerOrchestrator* = "plan-orchestrator"
  PlanCallerDiscord* = "plan-discord"
  PlanCallerMattermost* = "plan-mattermost"
  ManagedTicketWorktreeDirName* = "tickets"
  ManagedLockDirName* = "locks"
  ManagedRepoLockName* = "repo.lock"
  ManagedAdminLockName* = "admin.lock"
  ManagedRepoLockPidFileName* = "pid"
  OrchestratorPidFileName* = "orchestrator.pid"
  TicketBranchPrefix* = "scriptorium/ticket-"
  CommitLockFileName* = "commit.lock"
  CommitLockStalenessSeconds* = 30
  CommitLockPollMs* = 100
  CommitLockMaxRetries* = 50

var
  processLock: Lock
  processLockInitialized = false

proc ensureProcessLockInitialized*() =
  ## Initialize the global process creation lock once.
  if not processLockInitialized:
    initLock(processLock)
    processLockInitialized = true

proc acquireProcessLock() =
  ## Acquire the global process lock, initializing if needed.
  ensureProcessLockInitialized()
  {.cast(gcsafe).}:
    acquire(processLock)

proc releaseProcessLock() =
  ## Release the global process lock.
  {.cast(gcsafe).}:
    release(processLock)

proc cleanStaleGitLocks*(repoPath: string) =
  ## Remove stale git lock files that may have been left behind on NFS.
  for lockRel in GitLockFiles:
    let lockPath = repoPath / lockRel
    if fileExists(lockPath):
      let age = epochTime() - getLastModificationTime(lockPath).toUnixFloat()
      if age > GitLockMaxAgeSeconds.float:
        logWarn(&"removing stale git lock: {lockRel} (age={age:.0f}s)")
        removeFile(lockPath)
  let worktreesDir = repoPath / ".git" / "worktrees"
  if dirExists(worktreesDir):
    for entry in walkDir(worktreesDir, relative = false):
      if entry.kind == pcDir:
        let lockPath = entry.path / "index.lock"
        if fileExists(lockPath):
          let age = epochTime() - getLastModificationTime(lockPath).toUnixFloat()
          if age > GitLockMaxAgeSeconds.float:
            let name = lastPathPart(entry.path)
            let lockRel = &"worktrees/{name}/index.lock"
            logWarn(&"removing stale git lock: {lockRel} (age={age:.0f}s)")
            removeFile(lockPath)

proc gitRunOnce(dir: string, argsSeq: seq[string]): tuple[exitCode: int, output: string] =
  ## Run a git subcommand once and return exit code and output.
  let allArgs = @["-C", dir] & argsSeq
  acquireProcessLock()
  let process = startProcess("git", args = allArgs, options = {poUsePath, poStdErrToStdOut})
  let output = process.outputStream.readAll()
  let rc = process.waitForExit(GitCommandTimeoutMs)
  if rc == -1 and running(process):
    process.kill()
  process.close()
  releaseProcessLock()
  if rc == -1:
    let argsStr = argsSeq.join(" ")
    raise newException(IOError, &"git {argsStr} timed out after {GitCommandTimeoutMs div 1000}s")
  result = (exitCode: rc, output: output)

proc gitRun*(dir: string, args: varargs[string]) =
  ## Run a git subcommand in dir, retrying once after cleaning stale locks.
  let argsSeq = @args
  let first = gitRunOnce(dir, argsSeq)
  if first.exitCode == 0:
    return
  if "lock" in first.output.toLowerAscii():
    cleanStaleGitLocks(dir)
    let retry = gitRunOnce(dir, argsSeq)
    if retry.exitCode == 0:
      return
    let argsStr = argsSeq.join(" ")
    raise newException(IOError, &"git {argsStr} failed after lock cleanup: {retry.output.strip()}")
  let argsStr = argsSeq.join(" ")
  raise newException(IOError, &"git {argsStr} failed: {first.output.strip()}")

proc gitCheck*(dir: string, args: varargs[string]): int =
  ## Run a git subcommand in dir and return its exit code.
  let allArgs = @["-C", dir] & @args
  acquireProcessLock()
  let process = startProcess("git", args = allArgs, options = {poUsePath, poStdErrToStdOut})
  discard process.outputStream.readAll()
  result = process.waitForExit(GitCommandTimeoutMs)
  if result == -1 and running(process):
    process.kill()
  process.close()
  releaseProcessLock()
  if result == -1:
    let argsStr = (@args).join(" ")
    raise newException(IOError, &"git {argsStr} timed out after {GitCommandTimeoutMs div 1000}s")

proc parseWorktreeConflictPath*(output: string): string =
  ## Extract a conflicting worktree path from git worktree add stderr output.
  let usedMarker = "worktree at '"
  let usedMarkerPos = output.rfind(usedMarker)
  if usedMarkerPos >= 0:
    let pathStart = usedMarkerPos + usedMarker.len
    let pathEnd = output.find('\'', pathStart)
    if pathEnd > pathStart:
      result = output[pathStart..<pathEnd].strip()
      return

  let registeredMarker = "fatal: '"
  let registeredMarkerPos = output.rfind(registeredMarker)
  if registeredMarkerPos >= 0:
    let pathStart = registeredMarkerPos + registeredMarker.len
    let missingMarker = "' is a missing but already registered worktree"
    let pathEnd = output.find(missingMarker, pathStart)
    if pathEnd > pathStart:
      result = output[pathStart..<pathEnd].strip()

proc normalizeAbsolutePath*(path: string): string =
  ## Return a normalized absolute path that always uses forward slashes.
  result = absolutePath(path).replace('\\', '/')

proc managedRepoRootPath*(repoPath: string): string =
  ## Return the managed state root path inside the target repository.
  result = absolutePath(repoPath / ManagedStateDirName)

proc managedWorktreeRootPath*(repoPath: string): string =
  ## Return the managed worktree root path for one repository.
  result = managedRepoRootPath(repoPath) / ManagedWorktreeDirName

proc managedPlanWorktreePath*(repoPath: string, caller: string): string =
  ## Return the managed plan worktree path for one caller role.
  result = managedWorktreeRootPath(repoPath) / caller

proc managedMasterWorktreePath*(repoPath: string): string =
  ## Return the managed master worktree path for one repository.
  result = managedWorktreeRootPath(repoPath) / ManagedMasterWorktreeName

proc managedTicketWorktreeRootPath*(repoPath: string): string =
  ## Return the managed ticket worktree root path for one repository.
  result = managedWorktreeRootPath(repoPath) / ManagedTicketWorktreeDirName

proc managedRepoLockPath*(repoPath: string): string =
  ## Return the managed repository lock path for one repository.
  result = managedRepoRootPath(repoPath) / ManagedLockDirName / ManagedRepoLockName

proc managedAdminLockPath*(repoPath: string): string =
  ## Return the admin lock path for one repository.
  result = managedRepoRootPath(repoPath) / ManagedLockDirName / ManagedAdminLockName

proc commitLockPath*(repoPath: string): string =
  ## Return the commit lock file path for one repository.
  result = managedRepoRootPath(repoPath) / CommitLockFileName

proc orchestratorPidPath*(repoPath: string): string =
  ## Return the orchestrator PID file path for one repository.
  result = managedRepoRootPath(repoPath) / OrchestratorPidFileName

proc forceRemoveDir(path: string) =
  ## Remove a directory tree, falling back to rm -rf if removeDir fails.
  try:
    removeDir(path)
  except OSError:
    let rmRc = execCmd(&"rm -rf {quoteShell(path)}")
    if rmRc != 0:
      let msg = &"rm -rf failed (rc={rmRc}): {path}"
      raise newException(OSError, msg)

proc isManagedWorktreePath*(repoPath: string, path: string): bool =
  ## Return true when path is under this repository's managed worktree root.
  let managedRoot = normalizeAbsolutePath(managedWorktreeRootPath(repoPath))
  let normalizedPath = normalizeAbsolutePath(path)
  result = normalizedPath.startsWith(managedRoot & "/")

proc recoverManagedWorktreeConflict*(repoPath: string, addOutput: string): bool =
  ## Remove stale managed worktree conflicts and prune stale worktree metadata.
  let conflictPath = parseWorktreeConflictPath(addOutput)
  if conflictPath.len == 0:
    result = false
  elif not isManagedWorktreePath(repoPath, conflictPath):
    result = false
  else:
    logWarn(&"recovering stale worktree conflict: {conflictPath}")
    let removeRc = gitCheck(repoPath, "worktree", "remove", "--force", conflictPath)
    if removeRc != 0:
      logWarn(&"worktree remove failed (rc={removeRc}): {conflictPath}")
    let pruneRc = gitCheck(repoPath, "worktree", "prune")
    if pruneRc != 0:
      logWarn(&"worktree prune failed (rc={pruneRc})")
    if dirExists(conflictPath):
      forceRemoveDir(conflictPath)
    result = true

proc addWorktreeWithRecovery*(repoPath: string, worktreePath: string, branch: string) =
  ## Add one git worktree path for one branch, recovering stale managed conflicts once.
  logDebug(&"worktree add: {worktreePath} ({branch})")
  createDir(parentDir(worktreePath))
  if dirExists(worktreePath):
    logDebug(&"worktree add: removing existing dir {worktreePath}")
    forceRemoveDir(worktreePath)

  # Prune stale worktree entries pointing to nonexistent paths.
  let pruneRc = gitCheck(repoPath, "worktree", "prune")
  if pruneRc != 0:
    logWarn(&"worktree prune failed (rc={pruneRc})")

  var recoveredConflict = false
  while true:
    acquireProcessLock()
    let addProcess = startProcess(
      "git",
      args = @["-C", repoPath, "worktree", "add", worktreePath, branch],
      options = {poUsePath, poStdErrToStdOut},
    )
    let addOutput = addProcess.outputStream.readAll()
    let addRc = addProcess.waitForExit()
    addProcess.close()
    releaseProcessLock()

    if addRc == 0:
      break

    if recoveredConflict or not recoverManagedWorktreeConflict(repoPath, addOutput):
      let addOutputText = addOutput.strip()
      raise newException(
        IOError,
        &"git worktree add {worktreePath} {branch} failed: {addOutputText}",
      )
    recoveredConflict = true
    if dirExists(worktreePath):
      forceRemoveDir(worktreePath)

proc hasPlanBranch*(repoPath: string): bool =
  ## Return true when the repository has the scriptorium plan branch.
  result = gitCheck(repoPath, "rev-parse", "--verify", PlanBranch) == 0

proc resolveDefaultBranch*(repoPath: string): string =
  ## Dynamically detect the default branch for the repository.
  ## Checks refs/remotes/origin/HEAD first, then probes for master, main, develop.
  acquireProcessLock()
  let symrefProcess = startProcess(
    "git",
    args = @["-C", repoPath, "symbolic-ref", "refs/remotes/origin/HEAD"],
    options = {poUsePath, poStdErrToStdOut},
  )
  let symrefOutput = symrefProcess.outputStream.readAll()
  let symrefRc = symrefProcess.waitForExit()
  symrefProcess.close()
  releaseProcessLock()
  if symrefRc == 0:
    let symref = symrefOutput.strip()
    let prefix = "refs/remotes/origin/"
    if symref.startsWith(prefix):
      result = symref[prefix.len..^1]
      return

  const ProbeBranches = ["master", "main", "develop"]
  for branch in ProbeBranches:
    if gitCheck(repoPath, "rev-parse", "--verify", branch) == 0:
      result = branch
      return

  raise newException(IOError, "cannot determine default branch: refs/remotes/origin/HEAD is not set and none of master, main, develop exist")

proc defaultBranchHeadCommit*(repoPath: string): string =
  ## Return the current default branch commit SHA.
  let branch = resolveDefaultBranch(repoPath)
  acquireProcessLock()
  let process = startProcess(
    "git",
    args = @["-C", repoPath, "rev-parse", branch],
    options = {poUsePath, poStdErrToStdOut},
  )
  let output = process.outputStream.readAll()
  let rc = process.waitForExit()
  process.close()
  releaseProcessLock()
  if rc != 0:
    let errMsg = output.strip()
    raise newException(IOError, &"git rev-parse {branch} failed: {errMsg}")
  result = output.strip()

proc listGitWorktreePaths*(repoPath: string): seq[string] =
  ## Return absolute worktree paths from git worktree list.
  let allArgs = @["-C", repoPath, "worktree", "list", "--porcelain"]
  acquireProcessLock()
  let process = startProcess("git", args = allArgs, options = {poUsePath, poStdErrToStdOut})
  let output = process.outputStream.readAll()
  let rc = process.waitForExit()
  process.close()
  releaseProcessLock()
  if rc != 0:
    raise newException(IOError, &"git worktree list failed: {output.strip()}")

  for line in output.splitLines():
    if line.startsWith("worktree "):
      result.add(line["worktree ".len..^1].strip())

proc runCommandCapture*(workingDir: string, command: string, args: seq[string], timeoutMs: int = 300_000): tuple[exitCode: int, output: string] =
  ## Run a process and return combined stdout/stderr with its exit code.
  # Lock around startProcess and close, but not during readAll/waitForExit
  # since this is used for long-running commands like make test.
  acquireProcessLock()
  let process = startProcess(
    command,
    workingDir = workingDir,
    args = args,
    options = {poUsePath, poStdErrToStdOut},
  )
  discard process.outputStream
  releaseProcessLock()
  let output = process.outputStream.readAll()
  let exitCode = process.waitForExit(timeoutMs)
  if exitCode == -1 and running(process):
    process.kill()
  acquireProcessLock()
  process.close()
  releaseProcessLock()
  if exitCode == -1:
    let cmdStr = command & " " & args.join(" ")
    raise newException(IOError, &"{cmdStr} timed out after {timeoutMs div 1000}s")
  result = (exitCode: exitCode, output: output)

proc atomicWriteFile*(path: string, content: string) =
  ## Write content to path atomically via a temp file and rename.
  let tmpPath = path & ".tmp"
  writeFile(tmpPath, content)
  try:
    moveFile(tmpPath, path)
  except OSError:
    # Fallback to direct write if rename fails (e.g. cross-device).
    writeFile(path, content)
    removeFile(tmpPath)

proc ensureGitignoreEntry(gitignorePath: string, entry: string, matchPatterns: openArray[string]) =
  ## Append entry to .gitignore if none of matchPatterns are already present.
  if fileExists(gitignorePath):
    let content = readFile(gitignorePath)
    for line in content.splitLines():
      let trimmed = line.strip()
      for pattern in matchPatterns:
        if trimmed == pattern:
          return
    var newContent = content
    if newContent.len > 0 and not newContent.endsWith("\n"):
      newContent.add("\n")
    newContent.add(entry & "\n")
    writeFile(gitignorePath, newContent)
  else:
    writeFile(gitignorePath, entry & "\n")

proc ensureScriptoriumIgnored*(repoPath: string) =
  ## Ensure .scriptorium/ and .env are gitignored in the target repository.
  let managedDir = repoPath / ManagedStateDirName
  createDir(managedDir)
  let gitignorePath = repoPath / ".gitignore"
  ensureGitignoreEntry(gitignorePath, ".scriptorium/", [".scriptorium/", ".scriptorium", ".*"])
  ensureGitignoreEntry(gitignorePath, ".env", [".env", ".*"])
  ensureGitignoreEntry(gitignorePath, "*.log", ["*.log"])
