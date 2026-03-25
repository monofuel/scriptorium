## Tests for pause flag file management.

import
  std/[os, tempfiles, unittest],
  scriptorium/[git_ops, pause_flag]

suite "pause flag":
  test "writePauseFlag creates the file and isPaused returns true":
    let tmp = createTempDir("pause_flag_write_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    check not isPaused(tmp)
    writePauseFlag(tmp)
    check isPaused(tmp)
    check fileExists(pauseFlagPath(tmp))

  test "removePauseFlag removes the file and isPaused returns false":
    let tmp = createTempDir("pause_flag_remove_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    writePauseFlag(tmp)
    check isPaused(tmp)

    removePauseFlag(tmp)
    check not isPaused(tmp)
    check not fileExists(pauseFlagPath(tmp))

  test "removePauseFlag on non-existent file does not raise":
    let tmp = createTempDir("pause_flag_noop_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    removePauseFlag(tmp)
    check not isPaused(tmp)

  test "writePauseFlag called twice does not raise":
    let tmp = createTempDir("pause_flag_idempotent_", "", getTempDir())
    defer: removeDir(tmp)
    createDir(tmp / ManagedStateDirName)

    writePauseFlag(tmp)
    writePauseFlag(tmp)
    check isPaused(tmp)
