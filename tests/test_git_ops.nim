## Unit tests for atomicWriteFile in git_ops.

import
  std/[os, unittest],
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
