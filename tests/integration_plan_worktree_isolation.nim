## Integration tests for per-caller plan worktree isolation.

import
  std/[locks, os, osproc, strutils, unittest],
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
    ensurePlanWorktreeLockInitialized()

    # Create both worktrees via the production code path.
    var cliPath, orchPath: string
    {.cast(gcsafe).}:
      acquire(planWorktreeLock)
      cliPath = ensurePlanWorktreeReady(repoPath, PlanCallerCli)
      release(planWorktreeLock)

      acquire(planWorktreeLock)
      orchPath = ensurePlanWorktreeReady(repoPath, PlanCallerOrchestrator)
      release(planWorktreeLock)

    defer:
      teardownPlanWorktree(repoPath, PlanCallerCli)
      teardownPlanWorktree(repoPath, PlanCallerOrchestrator)

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

    # Create both worktrees via the production code path.
    var cliPath, orchPath: string
    {.cast(gcsafe).}:
      acquire(planWorktreeLock)
      cliPath = ensurePlanWorktreeReady(repoPath, PlanCallerCli)
      release(planWorktreeLock)

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
