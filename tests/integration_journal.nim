## Tests for write-ahead journal infrastructure.

import
  std/[json, os, osproc, strformat, strutils, unittest],
  scriptorium/journal

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

suite "journal file structure":
  test "journalExists returns false when no journal":
    let tmpDir = getTempDir() / "scriptorium_test_journal_noexist"
    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    check not journalExists(tmpDir)

  test "journal serialization round-trip":
    let tmpDir = getTempDir() / "scriptorium_test_journal_roundtrip"
    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    let steps = @[
      newWriteStep("tickets/0001.md", "ticket content"),
      newMoveStep("tickets/backlog/0002.md", "tickets/in-progress/0002.md"),
      newRemoveStep("tickets/done/0003.md"),
    ]

    let jPath = tmpDir / JournalFileName
    let journal = Journal(
      operation: "test-op",
      timestamp: "2026-01-01T00:00:00Z",
      steps: steps,
      commitMessage: "test commit message",
    )
    let jsonContent = pretty(journalToJson(journal))
    writeFile(jPath, jsonContent)

    check journalExists(tmpDir)

    let loaded = readJournal(tmpDir)
    check loaded.operation == "test-op"
    check loaded.timestamp == "2026-01-01T00:00:00Z"
    check loaded.commitMessage == "test commit message"
    check loaded.steps.len == 3
    check loaded.steps[0].action == jsWrite
    check loaded.steps[0].path == "tickets/0001.md"
    check loaded.steps[0].content == "ticket content"
    check loaded.steps[0].contentHash.len > 0
    check loaded.steps[1].action == jsMove
    check loaded.steps[1].source == "tickets/backlog/0002.md"
    check loaded.steps[1].destination == "tickets/in-progress/0002.md"
    check loaded.steps[2].action == jsRemove
    check loaded.steps[2].path == "tickets/done/0003.md"

suite "normal transition completion":
  test "begin execute complete removes journal":
    let tmpDir = getTempDir() / "scriptorium_test_journal_normal"
    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    makeTestRepo(tmpDir)

    let steps = @[
      newWriteStep("output.txt", "hello world"),
    ]

    beginJournalTransition(tmpDir, "test-assign", steps, "assign ticket 0001")

    # Journal should exist after begin.
    check journalExists(tmpDir)

    # Begin commit should be present.
    let (logOut1, _) = execCmdEx("git -C " & tmpDir & " log -1 --format=%s")
    check logOut1.strip().contains("begin transition")

    executeJournalSteps(tmpDir)

    # File should exist after execution.
    check fileExists(tmpDir / "output.txt")
    check readFile(tmpDir / "output.txt") == "hello world"

    # Transition commit should be present.
    let (logOut2, _) = execCmdEx("git -C " & tmpDir & " log -1 --format=%s")
    check logOut2.strip() == "assign ticket 0001"

    completeJournalTransition(tmpDir)

    # Journal should be gone.
    check not journalExists(tmpDir)

    # Completion commit should be present.
    let (logOut3, _) = execCmdEx("git -C " & tmpDir & " log -1 --format=%s")
    check logOut3.strip() == "scriptorium: complete transition"

suite "replay/rollback recovery":
  test "all steps applied completes transition":
    let tmpDir = getTempDir() / "scriptorium_test_journal_all_applied"
    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    makeTestRepo(tmpDir)

    let steps = @[
      newWriteStep("file_a.txt", "content a"),
      newRemoveStep("README.md"),
    ]

    beginJournalTransition(tmpDir, "test-all", steps, "apply all steps")

    # Manually apply all steps without committing (simulating crash after execute).
    writeFile(tmpDir / "file_a.txt", "content a")
    removeFile(tmpDir / "README.md")

    replayOrRollbackJournal(tmpDir)

    check not journalExists(tmpDir)
    check fileExists(tmpDir / "file_a.txt")
    check not fileExists(tmpDir / "README.md")

    let (logOut, _) = execCmdEx("git -C " & tmpDir & " log -1 --format=%s")
    check logOut.strip() == "scriptorium: complete transition"

  test "no steps applied rolls back":
    let tmpDir = getTempDir() / "scriptorium_test_journal_none_applied"
    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    makeTestRepo(tmpDir)

    let steps = @[
      newWriteStep("new_file.txt", "new content"),
    ]

    beginJournalTransition(tmpDir, "test-none", steps, "should not apply")

    # No steps applied — simulate crash right after begin commit.
    replayOrRollbackJournal(tmpDir)

    check not journalExists(tmpDir)
    check not fileExists(tmpDir / "new_file.txt")
    check fileExists(tmpDir / "README.md")

    let (logOut, _) = execCmdEx("git -C " & tmpDir & " log -1 --format=%s")
    check logOut.strip() == "scriptorium: complete transition"

  test "partial steps applied replays remaining":
    let tmpDir = getTempDir() / "scriptorium_test_journal_partial"
    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    makeTestRepo(tmpDir)

    # Create a source file for the move step.
    writeFile(tmpDir / "source.txt", "move me")
    runCmdOrDie(&"git -C {tmpDir} add source.txt")
    runCmdOrDie(&"git -C {tmpDir} commit -m 'add source'")

    let steps = @[
      newWriteStep("written.txt", "written content"),
      newMoveStep("source.txt", "dest.txt"),
      newRemoveStep("README.md"),
    ]

    beginJournalTransition(tmpDir, "test-partial", steps, "partial replay")

    # Apply only the first step (simulating partial crash).
    writeFile(tmpDir / "written.txt", "written content")

    replayOrRollbackJournal(tmpDir)

    check not journalExists(tmpDir)
    check fileExists(tmpDir / "written.txt")
    check readFile(tmpDir / "written.txt") == "written content"
    check fileExists(tmpDir / "dest.txt")
    check not fileExists(tmpDir / "source.txt")
    check not fileExists(tmpDir / "README.md")

    let (logOut, _) = execCmdEx("git -C " & tmpDir & " log -1 --format=%s")
    check logOut.strip() == "scriptorium: complete transition"
