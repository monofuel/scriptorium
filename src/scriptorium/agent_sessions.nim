import
  std/[json, os, posix, sha1, strutils, times],
  jsony,
  ./[agent_runner_types]

type
  AgentSessionRecord* = object
    sessionId*: string
    identity*: string
    cwd*: string
    completed*: bool

proc runtimeStateDirectory*(workingDir: string): string =
  ## Keep private state outside tracked worktree files even without a gitignore.
  let gitPath = workingDir / ".git"
  if dirExists(gitPath): return gitPath / "scriptorium"
  if fileExists(gitPath):
    let reference = readFile(gitPath).strip()
    if not reference.startsWith("gitdir: "):
      raise newException(ValueError, "Invalid git worktree metadata: " & gitPath)
    return absolutePath(reference[8..^1], workingDir) / "scriptorium"
  workingDir / ".scriptorium"

proc sessionIdentity*(request: AgentRunRequest): string =
  ## Bind saved conversations to their assignment, executable and access policy.
  let profile = request.profile
  let value = %*{
    "cwd": absolutePath(request.workingDir), "key": request.conversationKey,
    "ticket": request.ticketId, "agent": request.acpAgent,
    "command": profile.command, "args": profile.args,
    "profile": $secureHash(profile.toJson()),
    "options": $secureHash(request.configOptions.toJson()),
    "homeDirectory": request.homeDirectory,
    "policy": $request.accessPolicy, "paths": request.allowedWritePaths,
    "model": request.model, "effort": request.reasoningEffort,
  }
  $secureHash($value)

proc sessionDirectory*(request: AgentRunRequest): string =
  ## Locate runtime metadata outside the agent's tracked project files.
  if request.sessionRoot.len > 0: request.sessionRoot
  else: runtimeStateDirectory(request.workingDir) / "sessions"

proc atomicRuntimeWrite*(path, content: string) =
  ## Replace one runtime record atomically without exposing partial JSON.
  createDir(path.parentDir)
  let temporary = path & "." & $getCurrentProcessId() & "." & $getThreadId() & ".tmp"
  let output = open(temporary, fmWrite)
  try:
    output.write(content)
    output.flushFile()
    if posix.fsync(output.getFileHandle()) != 0: raiseOSError(osLastError())
  finally:
    output.close()
  moveFile(temporary, path)
  let directoryFd = posix.open(path.parentDir.cstring, O_RDONLY)
  if directoryFd < 0: raiseOSError(osLastError())
  defer: discard posix.close(directoryFd)
  if posix.fsync(directoryFd) != 0: raiseOSError(osLastError())

proc saveSessionRecord*(request: AgentRunRequest, sessionId: string,
    completed = false) =
  ## Persist identity without storing authentication or private MCP endpoints.
  let
    identity = sessionIdentity(request)
    directory = sessionDirectory(request)
    content = $(%*{"sessionId": sessionId, "identity": identity,
      "cwd": absolutePath(request.workingDir), "completed": completed,
      "updatedAt": epochTime()})
  atomicRuntimeWrite(directory / (identity & ".json"), content)
  atomicRuntimeWrite(directory / ($secureHash(sessionId) & ".json"), content)

proc readSessionRecord*(request: AgentRunRequest): AgentSessionRecord =
  ## Find a matching interrupted assignment or an explicitly requested session.
  let
    identity = sessionIdentity(request)
    key = if request.resumeSessionId.len > 0: $secureHash(request.resumeSessionId)
      else: identity
    path = sessionDirectory(request) / (key & ".json")
  if not fileExists(path):
    if request.resumeSessionId.len > 0:
      raise newException(ValueError, "Unknown saved ACP session: " & request.resumeSessionId)
    return
  let node = parseFile(path)
  result = AgentSessionRecord(sessionId: node["sessionId"].getStr(),
    identity: node["identity"].getStr(), cwd: node["cwd"].getStr(),
    completed: node["completed"].getBool())
  if result.identity != identity:
    raise newException(ValueError, "Saved ACP session does not match this conversation or access policy")

proc completeSessionsForWorktree*(directory, worktree: string) =
  ## Retire assignment conversations after their terminal Git transition commits.
  if not dirExists(directory): return
  for path in walkFiles(directory / "*.json"):
    let record = parseFile(path)
    if record["cwd"].getStr() == absolutePath(worktree):
      record["completed"] = %true
      atomicRuntimeWrite(path, $record)
