## Tests for prior work detection on ticket branches.

import
  std/[os, osproc, strformat, strutils, unittest],
  scriptorium/[coding_agent, prompt_builders]

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

suite "detectPriorWork":
  test "no prior commits returns zero":
    let tmpDir = getTempDir() / "scriptorium_test_prior_none"
    let repoPath = tmpDir / "repo"
    let worktreePath = tmpDir / "wt"
    let branch = "scriptorium/ticket-test-prior-none"

    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer:
      discard execCmdEx("git -C " & repoPath & " worktree remove --force " & worktreePath)
      removeDir(tmpDir)

    makeTestRepo(repoPath)
    # Create master ref so master..HEAD works.
    runCmdOrDie(&"git -C {repoPath} branch -M master")
    runCmdOrDie(&"git -C {repoPath} branch {branch}")
    runCmdOrDie(&"git -C {repoPath} worktree add {worktreePath} {branch}")

    let count = detectPriorWork(worktreePath, "test-prior-none")
    check count == 0

  test "prior commits detected with correct count":
    let tmpDir = getTempDir() / "scriptorium_test_prior_found"
    let repoPath = tmpDir / "repo"
    let worktreePath = tmpDir / "wt"
    let branch = "scriptorium/ticket-test-prior-found"

    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer:
      discard execCmdEx("git -C " & repoPath & " worktree remove --force " & worktreePath)
      removeDir(tmpDir)

    makeTestRepo(repoPath)
    runCmdOrDie(&"git -C {repoPath} branch -M master")
    runCmdOrDie(&"git -C {repoPath} branch {branch}")
    runCmdOrDie(&"git -C {repoPath} worktree add {worktreePath} {branch}")

    # Add two commits ahead of master in the worktree.
    writeFile(worktreePath / "file1.txt", "change 1")
    runCmdOrDie(&"git -C {worktreePath} add file1.txt")
    runCmdOrDie(&"git -C {worktreePath} commit -m 'first change'")

    writeFile(worktreePath / "file2.txt", "change 2")
    runCmdOrDie(&"git -C {worktreePath} add file2.txt")
    runCmdOrDie(&"git -C {worktreePath} commit -m 'second change'")

    let count = detectPriorWork(worktreePath, "test-prior-found")
    check count == 2

suite "buildCodingAgentPrompt with prior work":
  test "no prior work note leaves prompt unchanged":
    let prompt = buildCodingAgentPrompt("/repo", "/wt", "tickets/t.md", "ticket body", "")
    check "Prior Work Detected" notin prompt

  test "prior work note is appended to prompt":
    let note = "## Prior Work Detected\n\nThis branch has 3 commit(s) from a prior attempt."
    let prompt = buildCodingAgentPrompt("/repo", "/wt", "tickets/t.md", "ticket body", note)
    check "Prior Work Detected" in prompt
    check "3 commit(s)" in prompt
