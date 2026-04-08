## Tests for worktree creation, recovery, and ticket worktree lifecycle.

import
  std/[locks, os, osproc, strformat, strutils, unittest],
  scriptorium/[git_ops, lock_management, ticket_assignment]

proc makeTestRepo(path: string) =
  ## Create a minimal git repository at path suitable for testing.
  if dirExists(path):
    removeDir(path)
  createDir(path)
  discard execCmdEx("git -C " & path & " init")
  discard execCmdEx("git -C " & path & " config user.email test@test.com")
  discard execCmdEx("git -C " & path & " config user.name Test")
  writeFile(path / "README.md", "initial")
  discard execCmdEx("git -C " & path & " add README.md")
  discard execCmdEx("git -C " & path & " commit -m initial")

proc runCmdOrDie(cmd: string) =
  ## Run a shell command and fail the test immediately if it exits non-zero.
  let (output, rc) = execCmdEx(cmd)
  doAssert rc == 0, cmd & ": " & output

suite "addWorktreeWithRecovery":
  test "creates worktree for existing branch":
    let tmpDir = getTempDir() / "scriptorium_test_wt_add_normal"
    let repoPath = tmpDir / "repo"
    let worktreePath = tmpDir / "wt"
    let branch = "scriptorium/ticket-test-add"

    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer:
      discard execCmdEx("git -C " & repoPath & " worktree remove --force " & worktreePath)
      removeDir(tmpDir)

    makeTestRepo(repoPath)
    runCmdOrDie(&"git -C {repoPath} branch {branch}")
    addWorktreeWithRecovery(repoPath, worktreePath, branch)

    check dirExists(worktreePath)
    let (statusOut, statusRc) = execCmdEx("git -C " & worktreePath & " status --porcelain")
    check statusRc == 0
    let (branchOut, _) = execCmdEx("git -C " & worktreePath & " rev-parse --abbrev-ref HEAD")
    check branchOut.strip() == branch

  test "removes pre-existing directory before adding":
    let tmpDir = getTempDir() / "scriptorium_test_wt_add_existing"
    let repoPath = tmpDir / "repo"
    let worktreePath = tmpDir / "wt"
    let branch = "scriptorium/ticket-test-existing"

    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer:
      discard execCmdEx("git -C " & repoPath & " worktree remove --force " & worktreePath)
      removeDir(tmpDir)

    makeTestRepo(repoPath)
    runCmdOrDie(&"git -C {repoPath} branch {branch}")

    # Place a stale file in the target directory.
    createDir(worktreePath)
    writeFile(worktreePath / "stale.txt", "leftover")

    addWorktreeWithRecovery(repoPath, worktreePath, branch)

    check dirExists(worktreePath)
    check not fileExists(worktreePath / "stale.txt")
    let (statusOut, statusRc) = execCmdEx("git -C " & worktreePath & " status --porcelain")
    check statusRc == 0

  test "recovers stale managed worktree conflict":
    let tmpDir = getTempDir() / "scriptorium_test_wt_add_conflict"
    let repoPath = tmpDir / "repo"
    let branch = "scriptorium/ticket-test-conflict"

    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    makeTestRepo(repoPath)
    runCmdOrDie(&"git -C {repoPath} branch {branch}")

    # Create a worktree at a managed path, then delete the directory to simulate
    # a crash. Git metadata still references this path.
    let managedRoot = managedWorktreeRootPath(repoPath)
    let stalePath = managedRoot / "stale-wt"
    createDir(parentDir(stalePath))
    runCmdOrDie(&"git -C {repoPath} worktree add {stalePath} {branch}")
    removeDir(stalePath)

    # Now try to add a new worktree for the same branch at a different managed path.
    # This should fail initially (branch is "checked out" at the stale path) but
    # addWorktreeWithRecovery should detect and recover the conflict.
    let newPath = managedRoot / "recovered-wt"
    addWorktreeWithRecovery(repoPath, newPath, branch)
    defer: discard execCmdEx("git -C " & repoPath & " worktree remove --force " & newPath)

    check dirExists(newPath)
    let (branchOut, _) = execCmdEx("git -C " & newPath & " rev-parse --abbrev-ref HEAD")
    check branchOut.strip() == branch

  test "recoverManagedWorktreeConflict rejects non-managed path":
    let tmpDir = getTempDir() / "scriptorium_test_wt_nonmanaged"
    let repoPath = tmpDir / "repo"

    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    makeTestRepo(repoPath)

    # Simulate git stderr pointing to a path outside .scriptorium/worktrees/.
    let fakeOutput = "fatal: 'some-branch' is already used by worktree at '/tmp/external/wt'"
    check not recoverManagedWorktreeConflict(repoPath, fakeOutput)

suite "ensureWorktreeCreated":
  test "fresh creation returns correct branch and path":
    let tmpDir = getTempDir() / "scriptorium_test_ensure_fresh"

    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    makeTestRepo(tmpDir)
    let ticketRel = "tickets/in-progress/0001-test-ticket.md"
    let (branch, path) = ensureWorktreeCreated(tmpDir, ticketRel)

    check branch == "scriptorium/ticket-0001"
    check dirExists(path)

    let (branchOut, _) = execCmdEx("git -C " & path & " rev-parse --abbrev-ref HEAD")
    check branchOut.strip() == branch

    # Clean up worktree.
    discard execCmdEx("git -C " & tmpDir & " worktree remove --force " & path)

  test "re-creation when branch already exists":
    let tmpDir = getTempDir() / "scriptorium_test_ensure_branch_exists"

    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    makeTestRepo(tmpDir)
    let ticketRel = "tickets/in-progress/0002-preexisting.md"

    # Pre-create the branch.
    runCmdOrDie(&"git -C {tmpDir} branch scriptorium/ticket-0002")

    let (branch, path) = ensureWorktreeCreated(tmpDir, ticketRel)
    check branch == "scriptorium/ticket-0002"
    check dirExists(path)

    let (statusOut, statusRc) = execCmdEx("git -C " & path & " status --porcelain")
    check statusRc == 0

    discard execCmdEx("git -C " & tmpDir & " worktree remove --force " & path)

  test "re-creation when worktree directory lingers":
    let tmpDir = getTempDir() / "scriptorium_test_ensure_linger"

    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    makeTestRepo(tmpDir)
    let ticketRel = "tickets/in-progress/0003-linger.md"

    # First creation.
    let (branch1, path1) = ensureWorktreeCreated(tmpDir, ticketRel)
    check dirExists(path1)

    # Second creation for the same ticket should succeed.
    let (branch2, path2) = ensureWorktreeCreated(tmpDir, ticketRel)
    check branch2 == branch1
    check path2 == path1
    check dirExists(path2)

    let (statusOut, statusRc) = execCmdEx("git -C " & path2 & " status --porcelain")
    check statusRc == 0

    discard execCmdEx("git -C " & tmpDir & " worktree remove --force " & path2)

  test "re-creation when git tracking entry is stale":
    let tmpDir = getTempDir() / "scriptorium_test_ensure_stale_tracking"

    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    makeTestRepo(tmpDir)
    let ticketRel = "tickets/in-progress/0004-stale.md"

    # First creation.
    let (_, path1) = ensureWorktreeCreated(tmpDir, ticketRel)
    check dirExists(path1)

    # Delete the directory but leave git tracking metadata.
    removeDir(path1)
    check not dirExists(path1)

    # Re-creation should handle the stale tracking entry.
    let (branch2, path2) = ensureWorktreeCreated(tmpDir, ticketRel)
    check dirExists(path2)

    let (branchOut, _) = execCmdEx("git -C " & path2 & " rev-parse --abbrev-ref HEAD")
    check branchOut.strip() == branch2

    discard execCmdEx("git -C " & tmpDir & " worktree remove --force " & path2)

suite "concurrent plan worktree creation":
  test "two callers can create plan worktrees for same branch":
    let tmpDir = getTempDir() / "scriptorium_test_plan_concurrent"
    let repoPath = tmpDir / "repo"

    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    makeTestRepo(repoPath)
    runCmdOrDie(&"git -C {repoPath} branch {PlanBranch}")
    ensurePlanWorktreeLockInitialized()

    # Create worktrees for two different callers sequentially.
    # The commit lock serializes them — the test verifies no "already checked out" error.
    var cliPath, orchPath: string
    {.cast(gcsafe).}:
      acquire(planWorktreeLock)
      cliPath = ensurePlanWorktreeReady(repoPath, PlanCallerCli)
      release(planWorktreeLock)

      acquire(planWorktreeLock)
      orchPath = ensurePlanWorktreeReady(repoPath, PlanCallerOrchestrator)
      release(planWorktreeLock)

    check dirExists(cliPath)
    check dirExists(orchPath)
    check cliPath != orchPath

    teardownPlanWorktree(repoPath, PlanCallerCli)
    teardownPlanWorktree(repoPath, PlanCallerOrchestrator)

  test "recoverManagedWorktreeConflict skips active worktree":
    let tmpDir = getTempDir() / "scriptorium_test_plan_skip_active"
    let repoPath = tmpDir / "repo"

    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    makeTestRepo(repoPath)
    runCmdOrDie(&"git -C {repoPath} branch {PlanBranch}")

    # Create a real worktree at a managed path.
    let managedRoot = managedWorktreeRootPath(repoPath)
    let activePath = managedRoot / "active-wt"
    createDir(parentDir(activePath))
    runCmdOrDie(&"git -C {repoPath} worktree add {activePath} {PlanBranch}")
    defer:
      discard execCmdEx(&"git -C {repoPath} worktree remove --force {activePath}")

    # Simulate conflict error pointing to the active worktree.
    let fakeOutput = &"fatal: '{PlanBranch}' is already used by worktree at '{activePath}'"
    check not recoverManagedWorktreeConflict(repoPath, fakeOutput)
