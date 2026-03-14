## Tests for worktree health validation before retry.

import
  std/[os, osproc, strformat, strutils, unittest],
  scriptorium/[coding_agent, git_ops]

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

suite "validateWorktreeHealth":
  test "clean worktree proceeds without extra operations":
    let tmpDir = getTempDir() / "scriptorium_test_health_clean"
    let repoPath = tmpDir / "repo"
    let worktreePath = tmpDir / "wt"
    let branch = "scriptorium/ticket-test-clean"

    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer:
      discard execCmdEx("git -C " & repoPath & " worktree remove --force " & worktreePath)
      removeDir(tmpDir)

    makeTestRepo(repoPath)
    runCmdOrDie(&"git -C {repoPath} branch {branch}")
    runCmdOrDie(&"git -C {repoPath} worktree add {worktreePath} {branch}")

    # Get the commit before the health check.
    let (commitBefore, _) = execCmdEx("git -C " & worktreePath & " rev-parse HEAD")

    validateWorktreeHealth(repoPath, worktreePath, branch, "test-clean", 2)

    # Commit should be unchanged — no new commit was created.
    let (commitAfter, _) = execCmdEx("git -C " & worktreePath & " rev-parse HEAD")
    check commitBefore.strip() == commitAfter.strip()

    # Worktree should still exist and be functional.
    let (statusOut, statusRc) = execCmdEx("git -C " & worktreePath & " status --porcelain")
    check statusRc == 0
    check statusOut.strip().len == 0

  test "dirty worktree commits uncommitted changes":
    let tmpDir = getTempDir() / "scriptorium_test_health_dirty"
    let repoPath = tmpDir / "repo"
    let worktreePath = tmpDir / "wt"
    let branch = "scriptorium/ticket-test-dirty"

    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer:
      discard execCmdEx("git -C " & repoPath & " worktree remove --force " & worktreePath)
      removeDir(tmpDir)

    makeTestRepo(repoPath)
    runCmdOrDie(&"git -C {repoPath} branch {branch}")
    runCmdOrDie(&"git -C {repoPath} worktree add {worktreePath} {branch}")

    # Create uncommitted changes.
    writeFile(worktreePath / "new_file.txt", "partial work")

    validateWorktreeHealth(repoPath, worktreePath, branch, "test-dirty", 3)

    # Worktree should now be clean.
    let (statusOut, statusRc) = execCmdEx("git -C " & worktreePath & " status --porcelain")
    check statusRc == 0
    check statusOut.strip().len == 0

    # The commit message should match the expected format.
    let (logOut, _) = execCmdEx("git -C " & worktreePath & " log -1 --format=%s")
    check logOut.strip() == "scriptorium: save partial agent work (attempt 3)"

  test "corrupt worktree is removed and recreated":
    let tmpDir = getTempDir() / "scriptorium_test_health_corrupt"
    let repoPath = tmpDir / "repo"
    let worktreePath = tmpDir / "wt"
    let branch = "scriptorium/ticket-test-corrupt"

    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer:
      discard execCmdEx("git -C " & repoPath & " worktree remove --force " & worktreePath)
      removeDir(tmpDir)

    makeTestRepo(repoPath)
    runCmdOrDie(&"git -C {repoPath} branch {branch}")
    runCmdOrDie(&"git -C {repoPath} worktree add {worktreePath} {branch}")

    # Corrupt the worktree by removing the .git file.
    let gitFile = worktreePath / ".git"
    removeFile(gitFile)
    writeFile(gitFile, "garbage")

    validateWorktreeHealth(repoPath, worktreePath, branch, "test-corrupt", 2)

    # Worktree should be recreated and functional.
    let (statusOut, statusRc) = execCmdEx("git -C " & worktreePath & " status --porcelain")
    check statusRc == 0
    check statusOut.strip().len == 0

    # Should be on the correct branch.
    let (branchOut, _) = execCmdEx("git -C " & worktreePath & " rev-parse --abbrev-ref HEAD")
    check branchOut.strip() == branch
