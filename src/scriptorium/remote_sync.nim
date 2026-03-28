import
  std/[strformat, strutils],
  ./[config, git_ops, logging, merge_queue]

type
  SyncMergeResult* = enum
    smrUpToDate
    smrFastForward
    smrMerged
    smrFailed

  SyncResult* = object
    fetchedRemotes*: int
    fetchFailures*: int
    mergeResult*: SyncMergeResult
    pushedRemotes*: int
    pushFailures*: int

proc listRemotes*(repoPath: string): seq[string] =
  ## Return the names of all configured git remotes.
  let capture = runCommandCapture(repoPath, "git", @["-C", repoPath, "remote"])
  if capture.exitCode != 0:
    logWarn(&"git remote failed: {capture.output.strip()}")
    return @[]
  for line in capture.output.splitLines():
    let name = line.strip()
    if name.len > 0:
      result.add(name)

proc fetchRemote*(repoPath: string, remote: string): int =
  ## Fetch from one remote. Returns exit code.
  let capture = runCommandCapture(repoPath, "git", @["-C", repoPath, "fetch", remote])
  if capture.exitCode != 0:
    let msg = capture.output.strip()
    logWarn(&"fetch {remote} failed: {msg}")
  result = capture.exitCode

proc fetchAllRemotes*(repoPath: string, remotes: seq[string]): tuple[fetched: int, failures: int] =
  ## Fetch from all given remotes. Returns count of successes and failures.
  for remote in remotes:
    let rc = fetchRemote(repoPath, remote)
    if rc == 0:
      inc result.fetched
    else:
      inc result.failures

proc mergeFromPrimary*(repoPath: string, primaryRemote: string, branch: string): SyncMergeResult =
  ## Merge the primary remote's branch into the local default branch.
  ## Uses fast-forward when possible, falls back to -X theirs for conflicts.
  let remoteBranch = primaryRemote & "/" & branch
  result = withMasterWorktree(repoPath, proc(masterPath: string): SyncMergeResult =
    # Check if already up to date.
    let diffCheck = runCommandCapture(masterPath, "git", @["diff", "--quiet", "HEAD", remoteBranch])
    if diffCheck.exitCode == 0:
      # Also check if HEAD and remote point to the same commit.
      let localHead = runCommandCapture(masterPath, "git", @["rev-parse", "HEAD"])
      let remoteHead = runCommandCapture(masterPath, "git", @["rev-parse", remoteBranch])
      if localHead.output.strip() == remoteHead.output.strip():
        return smrUpToDate

    # Try fast-forward first.
    let ffResult = runCommandCapture(masterPath, "git", @["merge", "--ff-only", remoteBranch])
    if ffResult.exitCode == 0:
      logInfo(&"remote sync: fast-forwarded to {remoteBranch}")
      return smrFastForward

    # Fast-forward failed (diverged). Merge with gitea winning conflicts.
    logInfo(&"remote sync: fast-forward failed, merging {remoteBranch} with -X theirs")
    let mergeResult = runCommandCapture(masterPath, "git", @["merge", "-X", "theirs", "--no-edit", remoteBranch])
    if mergeResult.exitCode == 0:
      logInfo(&"remote sync: merged {remoteBranch} with theirs strategy")
      return smrMerged

    # Merge failed entirely. Abort and report.
    let msg = mergeResult.output.strip()
    logWarn(&"remote sync: merge failed: {msg}")
    discard runCommandCapture(masterPath, "git", @["merge", "--abort"])
    return smrFailed
  )

proc pushToRemote*(repoPath: string, remote: string, branch: string): int =
  ## Push the branch to one remote. Returns exit code.
  let capture = runCommandCapture(repoPath, "git", @["-C", repoPath, "push", remote, branch])
  if capture.exitCode != 0:
    let msg = capture.output.strip()
    logWarn(&"push {remote} {branch} failed: {msg}")
  result = capture.exitCode

proc pushToAllRemotes*(repoPath: string, cfg: RemoteSyncConfig) =
  ## Push the default branch to all configured remotes.
  let branch = resolveDefaultBranch(repoPath)
  let remotes = if cfg.remotes.len > 0: cfg.remotes else: listRemotes(repoPath)
  for remote in remotes:
    let rc = pushToRemote(repoPath, remote, branch)
    if rc == 0:
      logDebug(&"remote sync: pushed {branch} to {remote}")
    else:
      logWarn(&"remote sync: push to {remote} failed (will retry next cycle)")

proc syncRemotes*(repoPath: string, cfg: RemoteSyncConfig): SyncResult =
  ## Run one full sync cycle: fetch all, merge from primary, push to all.
  let branch = resolveDefaultBranch(repoPath)
  let remotes = if cfg.remotes.len > 0: cfg.remotes else: listRemotes(repoPath)
  if remotes.len == 0:
    logDebug("remote sync: no remotes configured")
    return

  # Fetch all remotes.
  let fetchResult = fetchAllRemotes(repoPath, remotes)
  result.fetchedRemotes = fetchResult.fetched
  result.fetchFailures = fetchResult.failures

  # Merge from primary remote.
  let primaryRemote = cfg.primaryRemote
  if primaryRemote in remotes:
    result.mergeResult = mergeFromPrimary(repoPath, primaryRemote, branch)
  else:
    logWarn(&"remote sync: primary remote '{primaryRemote}' not found in remotes")
    result.mergeResult = smrUpToDate

  # Push to all remotes.
  for remote in remotes:
    let rc = pushToRemote(repoPath, remote, branch)
    if rc == 0:
      inc result.pushedRemotes
    else:
      inc result.pushFailures
