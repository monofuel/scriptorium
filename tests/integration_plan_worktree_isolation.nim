## Integration tests for per-caller plan worktree isolation.

import
  std/[locks, os, osproc, strformat, strutils, unittest],
  scriptorium/[git_ops, lock_management]

proc makeTestRepo(path: string) =
  ## Create a minimal git repository with a scriptorium/plan branch.
  if dirExists(path):
    removeDir(path)
  createDir(path)
  discard execCmdEx("git -C " & path & " init")
  discard execCmdEx("git -C " & path & " config user.email test@test.com")
  discard execCmdEx("git -C " & path & " config user.name Test")
  writeFile(path / "README.md", "initial")
  discard execCmdEx("git -C " & path & " add README.md")
  discard execCmdEx("git -C " & path & " commit -m initial")
  discard execCmdEx("git -C " & path & " branch " & PlanBranch)

proc addDetachedWorktree(repoPath: string, worktreePath: string, branch: string) =
  ## Add a worktree with detached HEAD at a branch tip.
  createDir(parentDir(worktreePath))
  let cmd = &"git -C {repoPath} worktree add --detach {worktreePath} {branch}"
  let (output, rc) = execCmdEx(cmd)
  doAssert rc == 0, &"git worktree add --detach failed: {output}"

suite "per-caller plan worktree isolation":
  test "different callers get separate worktree paths":
    let tmpDir = getTempDir() / "scriptorium_test_plan_isolation_paths"
    let repoPath = tmpDir / "repo"

    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    makeTestRepo(repoPath)

    let cliPath = managedPlanWorktreePath(repoPath, PlanCallerCli)
    let orchPath = managedPlanWorktreePath(repoPath, PlanCallerOrchestrator)

    check cliPath != orchPath
    check cliPath.endsWith(PlanCallerCli)
    check orchPath.endsWith(PlanCallerOrchestrator)

  test "files in one worktree do not appear in another":
    let tmpDir = getTempDir() / "scriptorium_test_plan_isolation_state"
    let repoPath = tmpDir / "repo"

    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    makeTestRepo(repoPath)

    let cliPath = managedPlanWorktreePath(repoPath, PlanCallerCli)
    let orchPath = managedPlanWorktreePath(repoPath, PlanCallerOrchestrator)

    # Create both worktrees with detached HEAD so they can coexist.
    addDetachedWorktree(repoPath, cliPath, PlanBranch)
    addDetachedWorktree(repoPath, orchPath, PlanBranch)
    defer:
      discard execCmdEx(&"git -C {repoPath} worktree remove --force {cliPath}")
      discard execCmdEx(&"git -C {repoPath} worktree remove --force {orchPath}")

    writeFile(cliPath / "cli-only.txt", "hello from cli")

    check fileExists(cliPath / "cli-only.txt")
    check not fileExists(orchPath / "cli-only.txt")

  test "refreshing one worktree does not affect another":
    let tmpDir = getTempDir() / "scriptorium_test_plan_isolation_refresh"
    let repoPath = tmpDir / "repo"

    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    makeTestRepo(repoPath)
    ensurePlanWorktreeLockInitialized()

    # Create the cli worktree detached so it does not hold the branch.
    let cliPath = managedPlanWorktreePath(repoPath, PlanCallerCli)
    addDetachedWorktree(repoPath, cliPath, PlanBranch)

    # Create the orchestrator worktree via ensurePlanWorktreeReady so it
    # checks out the branch and performs reset --hard + clean -fd.
    var orchPath: string
    {.cast(gcsafe).}:
      acquire(planWorktreeLock)
      orchPath = ensurePlanWorktreeReady(repoPath, PlanCallerOrchestrator)
      release(planWorktreeLock)

    # Write an uncommitted file in the cli worktree.
    writeFile(cliPath / "uncommitted.txt", "work in progress")

    # Refresh the orchestrator worktree (git reset --hard + git clean -fd).
    {.cast(gcsafe).}:
      acquire(planWorktreeLock)
      discard ensurePlanWorktreeReady(repoPath, PlanCallerOrchestrator)
      release(planWorktreeLock)

    # The cli worktree file must survive the orchestrator refresh.
    check fileExists(cliPath / "uncommitted.txt")
    let content = readFile(cliPath / "uncommitted.txt")
    check content == "work in progress"

    teardownPlanWorktree(repoPath, PlanCallerCli)
    teardownPlanWorktree(repoPath, PlanCallerOrchestrator)
