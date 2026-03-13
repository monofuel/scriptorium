import
  std/[os, osproc, streams, strformat, strutils]

const
  GitCommandTimeoutMs* = 60_000
  PlanBranch* = "scriptorium/plan"
  ManagedStateRootDirName* = "scriptorium"
  ManagedWorktreeDirName* = "worktrees"
  ManagedPlanWorktreeName* = "plan"
  ManagedMasterWorktreeName* = "master"
  ManagedTicketWorktreeDirName* = "tickets"
  ManagedLockDirName* = "locks"
  ManagedRepoLockName* = "repo.lock"
  ManagedRepoLockPidFileName* = "pid"
  LegacyManagedWorktreeRoot* = ".scriptorium/worktrees"
  TicketBranchPrefix* = "scriptorium/ticket-"

proc gitRun*(dir: string, args: varargs[string]) =
  ## Run a git subcommand in dir and raise an IOError on non-zero exit.
  let argsSeq = @args
  let allArgs = @["-C", dir] & argsSeq
  let process = startProcess("git", args = allArgs, options = {poUsePath, poStdErrToStdOut})
  let output = process.outputStream.readAll()
  let rc = process.waitForExit(GitCommandTimeoutMs)
  if rc == -1 and running(process):
    process.kill()
    process.close()
    let argsStr = argsSeq.join(" ")
    raise newException(IOError, fmt"git {argsStr} timed out after {GitCommandTimeoutMs div 1000}s")
  process.close()
  if rc != 0:
    let argsStr = argsSeq.join(" ")
    raise newException(IOError, fmt"git {argsStr} failed: {output.strip()}")

proc gitCheck*(dir: string, args: varargs[string]): int =
  ## Run a git subcommand in dir and return its exit code.
  let allArgs = @["-C", dir] & @args
  let process = startProcess("git", args = allArgs, options = {poUsePath, poStdErrToStdOut})
  discard process.outputStream.readAll()
  result = process.waitForExit(GitCommandTimeoutMs)
  if result == -1 and running(process):
    process.kill()
    process.close()
    let argsStr = (@args).join(" ")
    raise newException(IOError, fmt"git {argsStr} timed out after {GitCommandTimeoutMs div 1000}s")
  process.close()

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

proc repoStateKey*(repoPath: string): string =
  ## Build a deterministic state key from one repository absolute path.
  let canonicalRepoPath = normalizeAbsolutePath(repoPath)
  let rawRepoName = extractFilename(canonicalRepoPath)
  let repoName = if rawRepoName.len > 0: rawRepoName else: "repo"

  var hashValue = 1469598103934665603'u64
  for ch in canonicalRepoPath:
    hashValue = (hashValue xor uint64(ord(ch))) * 1099511628211'u64
  let hashText = toLowerAscii(toHex(hashValue, 16))
  result = repoName.toLowerAscii() & "-" & hashText

proc managedRepoRootPath*(repoPath: string): string =
  ## Return the deterministic managed state root path in /tmp for one repository.
  let repoKey = repoStateKey(repoPath)
  result = absolutePath(getTempDir() / ManagedStateRootDirName / repoKey)

proc managedWorktreeRootPath*(repoPath: string): string =
  ## Return the deterministic managed worktree root path in /tmp for one repository.
  result = managedRepoRootPath(repoPath) / ManagedWorktreeDirName

proc managedPlanWorktreePath*(repoPath: string): string =
  ## Return the deterministic plan worktree path in /tmp for one repository.
  result = managedWorktreeRootPath(repoPath) / ManagedPlanWorktreeName

proc managedMasterWorktreePath*(repoPath: string): string =
  ## Return the deterministic master worktree path in /tmp for one repository.
  result = managedWorktreeRootPath(repoPath) / ManagedMasterWorktreeName

proc managedTicketWorktreeRootPath*(repoPath: string): string =
  ## Return the deterministic ticket worktree root path in /tmp for one repository.
  result = managedWorktreeRootPath(repoPath) / ManagedTicketWorktreeDirName

proc managedRepoLockPath*(repoPath: string): string =
  ## Return the deterministic repository lock path in /tmp for one repository.
  result = managedRepoRootPath(repoPath) / ManagedLockDirName / ManagedRepoLockName

proc isManagedWorktreePath*(repoPath: string, path: string): bool =
  ## Return true when path is under this repository's managed /tmp worktree root.
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
    discard gitCheck(repoPath, "worktree", "remove", "--force", conflictPath)
    discard gitCheck(repoPath, "worktree", "prune")
    if dirExists(conflictPath):
      removeDir(conflictPath)
    result = true

proc addWorktreeWithRecovery*(repoPath: string, worktreePath: string, branch: string) =
  ## Add one git worktree path for one branch, recovering stale managed conflicts once.
  createDir(parentDir(worktreePath))
  if dirExists(worktreePath):
    removeDir(worktreePath)

  # Prune stale worktree entries pointing to nonexistent paths.
  discard gitCheck(repoPath, "worktree", "prune")

  var recoveredConflict = false
  while true:
    let addProcess = startProcess(
      "git",
      args = @["-C", repoPath, "worktree", "add", worktreePath, branch],
      options = {poUsePath, poStdErrToStdOut},
    )
    let addOutput = addProcess.outputStream.readAll()
    let addRc = addProcess.waitForExit()
    addProcess.close()

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
      removeDir(worktreePath)

proc hasPlanBranch*(repoPath: string): bool =
  ## Return true when the repository has the scriptorium plan branch.
  result = gitCheck(repoPath, "rev-parse", "--verify", PlanBranch) == 0

proc masterHeadCommit*(repoPath: string): string =
  ## Return the current master branch commit SHA.
  let process = startProcess(
    "git",
    args = @["-C", repoPath, "rev-parse", "master"],
    options = {poUsePath, poStdErrToStdOut},
  )
  let output = process.outputStream.readAll()
  let rc = process.waitForExit()
  process.close()
  if rc != 0:
    raise newException(IOError, fmt"git rev-parse master failed: {output.strip()}")
  result = output.strip()

proc listGitWorktreePaths*(repoPath: string): seq[string] =
  ## Return absolute worktree paths from git worktree list.
  let allArgs = @["-C", repoPath, "worktree", "list", "--porcelain"]
  let process = startProcess("git", args = allArgs, options = {poUsePath, poStdErrToStdOut})
  let output = process.outputStream.readAll()
  let rc = process.waitForExit()
  process.close()
  if rc != 0:
    raise newException(IOError, fmt"git worktree list failed: {output.strip()}")

  for line in output.splitLines():
    if line.startsWith("worktree "):
      result.add(line["worktree ".len..^1].strip())

proc runCommandCapture*(workingDir: string, command: string, args: seq[string], timeoutMs: int = 300_000): tuple[exitCode: int, output: string] =
  ## Run a process and return combined stdout/stderr with its exit code.
  let process = startProcess(
    command,
    workingDir = workingDir,
    args = args,
    options = {poUsePath, poStdErrToStdOut},
  )
  let output = process.outputStream.readAll()
  let exitCode = process.waitForExit(timeoutMs)
  if exitCode == -1 and running(process):
    process.kill()
    process.close()
    let cmdStr = command & " " & args.join(" ")
    raise newException(IOError, fmt"{cmdStr} timed out after {timeoutMs div 1000}s")
  process.close()
  result = (exitCode: exitCode, output: output)

proc cleanupLegacyManagedTicketWorktrees*(repoPath: string): seq[string] =
  ## Remove legacy repo-local managed ticket worktrees from older versions.
  let legacyRoot = normalizeAbsolutePath(repoPath / LegacyManagedWorktreeRoot)
  for path in listGitWorktreePaths(repoPath):
    let normalizedPath = normalizeAbsolutePath(path)
    if normalizedPath.startsWith(legacyRoot & "/"):
      discard gitCheck(repoPath, "worktree", "remove", "--force", path)
      if dirExists(path):
        removeDir(path)
      result.add(path)

  if dirExists(legacyRoot):
    removeDir(legacyRoot)
