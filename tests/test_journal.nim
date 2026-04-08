## Unit tests for journal module.

import
  std/[os, osproc, strutils],
  scriptorium/[journal, logging]

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

proc testCorruptedJournalRecovery() =
  ## Verify replayOrRollbackJournal handles a corrupted journal file gracefully.
  let tmpDir = getTempDir() / "scriptorium_test_journal_corrupt"
  makeTestRepo(tmpDir)
  defer: removeDir(tmpDir)

  # Write a corrupted (non-JSON) journal file.
  writeFile(tmpDir / JournalFileName, "NOT VALID JSON {{{{")

  captureLogs = true
  capturedLogs = @[]
  defer:
    captureLogs = false
    capturedLogs = @[]

  # Should not raise.
  replayOrRollbackJournal(tmpDir)

  # Journal file should be removed.
  doAssert not fileExists(tmpDir / JournalFileName),
    "corrupted journal file should be deleted after recovery"

  # A warning should have been logged.
  var foundWarning = false
  for entry in capturedLogs:
    if entry.level == lvlWarn and "corrupted journal" in entry.msg:
      foundWarning = true
      break
  doAssert foundWarning, "expected a warning log about corrupted journal"
  echo "[OK] corrupted journal recovery works without crashing"

proc testTruncatedJsonJournalRecovery() =
  ## Verify replayOrRollbackJournal handles truncated JSON gracefully.
  let tmpDir = getTempDir() / "scriptorium_test_journal_truncated"
  makeTestRepo(tmpDir)
  defer: removeDir(tmpDir)

  # Write truncated JSON (simulates crash mid-write).
  writeFile(tmpDir / JournalFileName, """{"operation": "test", "timestamp": "2026-01-01T00:00:00Z", "steps": [""")

  captureLogs = true
  capturedLogs = @[]
  defer:
    captureLogs = false
    capturedLogs = @[]

  replayOrRollbackJournal(tmpDir)

  doAssert not fileExists(tmpDir / JournalFileName),
    "truncated journal file should be deleted after recovery"
  echo "[OK] truncated JSON journal recovery works without crashing"

proc testEmptyJournalFileRecovery() =
  ## Verify replayOrRollbackJournal handles an empty journal file gracefully.
  let tmpDir = getTempDir() / "scriptorium_test_journal_empty"
  makeTestRepo(tmpDir)
  defer: removeDir(tmpDir)

  writeFile(tmpDir / JournalFileName, "")

  captureLogs = true
  capturedLogs = @[]
  defer:
    captureLogs = false
    capturedLogs = @[]

  replayOrRollbackJournal(tmpDir)

  doAssert not fileExists(tmpDir / JournalFileName),
    "empty journal file should be deleted after recovery"
  echo "[OK] empty journal file recovery works without crashing"

when isMainModule:
  testCorruptedJournalRecovery()
  testTruncatedJsonJournalRecovery()
  testEmptyJournalFileRecovery()
