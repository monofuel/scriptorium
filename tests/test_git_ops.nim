## Unit tests for git_ops: atomicWriteFile, worktree conflict parsing, managed
## path checks, directory removal, and default branch resolution.

import
  std/[os, osproc, tempfiles, unittest],
  scriptorium/git_ops

suite "atomicWriteFile":
  var tmpDir: string

  setup:
    tmpDir = getTempDir() / "test_git_ops_atomic"
    createDir(tmpDir)

  teardown:
    removeDir(tmpDir)

  test "writes correct content to new file":
    let path = tmpDir / "new_file.txt"
    atomicWriteFile(path, "hello world\n")
    check readFile(path) == "hello world\n"

  test "no leftover .tmp file after successful write":
    let path = tmpDir / "clean.txt"
    atomicWriteFile(path, "data")
    check not fileExists(path & ".tmp")

  test "overwrites existing file atomically":
    let path = tmpDir / "overwrite.txt"
    writeFile(path, "old content")
    atomicWriteFile(path, "new content")
    check readFile(path) == "new content"

  test "empty content produces empty file":
    let path = tmpDir / "empty.txt"
    atomicWriteFile(path, "")
    check readFile(path) == ""

  test "existing file is not corrupted when tmp write succeeds":
    let path = tmpDir / "stable.txt"
    writeFile(path, "original")
    atomicWriteFile(path, "replaced")
    # The file should contain the new content, not a mix.
    let content = readFile(path)
    check content == "replaced"

suite "parseWorktreeConflictPath":
  test "extracts path from worktree-at conflict":
    let output = "fatal: 'scriptorium/ticket-0001' is already used by worktree at '/tmp/scriptorium/worktrees/tickets/0001-foo'"
    check parseWorktreeConflictPath(output) == "/tmp/scriptorium/worktrees/tickets/0001-foo"

  test "extracts path from registered-missing worktree":
    let output = "fatal: '/tmp/stale/wt' is a missing but already registered worktree"
    check parseWorktreeConflictPath(output) == "/tmp/stale/wt"

  test "returns empty for non-conflict output":
    let output = "Preparing worktree (checking out 'main')"
    check parseWorktreeConflictPath(output) == ""

  test "returns empty for empty input":
    check parseWorktreeConflictPath("") == ""

  test "handles path with spaces":
    let output = "fatal: 'branch' is already used by worktree at '/path with spaces/wt'"
    check parseWorktreeConflictPath(output) == "/path with spaces/wt"

  test "returns empty when closing quote is missing":
    let output = "worktree at '/unclosed"
    check parseWorktreeConflictPath(output) == ""

suite "isManagedWorktreePath":
  test "true for path under managed worktree root":
    let repo = "/tmp/test-repo"
    let managed = repo / ManagedStateDirName / ManagedWorktreeDirName / "plan-cli"
    check isManagedWorktreePath(repo, managed)

  test "false for path outside managed root":
    check not isManagedWorktreePath("/tmp/test-repo", "/other/path")

  test "false for the managed root itself":
    let repo = "/tmp/test-repo"
    let root = repo / ManagedStateDirName / ManagedWorktreeDirName
    check not isManagedWorktreePath(repo, root)

  test "false for prefix-of but not under":
    let repo = "/tmp/test-repo"
    let notUnder = repo / ManagedStateDirName / (ManagedWorktreeDirName & "-extra") / "foo"
    check not isManagedWorktreePath(repo, notUnder)

suite "forceRemoveDir":
  test "removes empty directory":
    let tmp = createTempDir("force_rm_empty_", "", getTempDir())
    check dirExists(tmp)
    forceRemoveDir(tmp)
    check not dirExists(tmp)

  test "removes non-empty directory":
    let tmp = createTempDir("force_rm_nonempty_", "", getTempDir())
    createDir(tmp / "sub" / "nested")
    writeFile(tmp / "sub" / "nested" / "file.txt", "content")
    writeFile(tmp / "top.txt", "top")
    forceRemoveDir(tmp)
    check not dirExists(tmp)

  test "no-op when directory does not exist":
    let path = getTempDir() / "force_rm_nonexistent_99999"
    check not dirExists(path)
    forceRemoveDir(path)
    check not dirExists(path)

suite "resolveDefaultBranchOrEmpty":
  test "returns empty for non-git directory":
    let tmp = createTempDir("resolve_branch_", "", getTempDir())
    defer: removeDir(tmp)
    check resolveDefaultBranchOrEmpty(tmp) == ""

  test "returns branch name for valid git repo":
    let tmp = createTempDir("resolve_branch_valid_", "", getTempDir())
    defer: removeDir(tmp)
    discard execCmd("git -C " & tmp & " init -b master")
    discard execCmd("git -C " & tmp & " commit --allow-empty -m init")
    check resolveDefaultBranchOrEmpty(tmp) == "master"

  test "resolveDefaultBranch raises for non-git directory":
    let tmp = createTempDir("resolve_branch_raise_", "", getTempDir())
    defer: removeDir(tmp)
    expect IOError:
      discard resolveDefaultBranch(tmp)

suite "validateGitDir":
  test "accepts directory with .git directory":
    let tmp = createTempDir("validate_gitdir_dir_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ".git")
    validateGitDir(tmp)

  test "accepts directory with .git file":
    let tmp = createTempDir("validate_gitdir_file_", "", getTempDir())
    defer: removeDir(tmp)
    writeFile(tmp / ".git", "gitdir: /some/path")
    validateGitDir(tmp)

  test "rejects directory without .git":
    let tmp = createTempDir("validate_gitdir_none_", "", getTempDir())
    defer: removeDir(tmp)
    expect IOError:
      validateGitDir(tmp)

  test "rejects non-existent directory":
    expect IOError:
      validateGitDir(getTempDir() / "validate_gitdir_nonexistent_99999")
