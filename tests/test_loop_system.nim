import
  std/[os, strutils],
  scriptorium/loop_system

proc testQueueDrainedAllEmpty() =
  ## Verify isQueueDrained returns true when all directories are empty.
  let tmpDir = getTempDir() / "test_loop_system_empty"
  createDir(tmpDir / "tickets" / "open")
  createDir(tmpDir / "tickets" / "in-progress")
  createDir(tmpDir / "queue" / "merge" / "pending")
  defer: removeDir(tmpDir)

  doAssert isQueueDrained(tmpDir) == true
  echo "[OK] isQueueDrained returns true when all directories are empty"

proc testQueueNotDrainedOpenTicket() =
  ## Verify isQueueDrained returns false when open has a markdown file.
  let tmpDir = getTempDir() / "test_loop_system_open"
  createDir(tmpDir / "tickets" / "open")
  createDir(tmpDir / "tickets" / "in-progress")
  createDir(tmpDir / "queue" / "merge" / "pending")
  writeFile(tmpDir / "tickets" / "open" / "0001-test.md", "ticket")
  defer: removeDir(tmpDir)

  doAssert isQueueDrained(tmpDir) == false
  echo "[OK] isQueueDrained returns false when open has a .md file"

proc testQueueNotDrainedInProgress() =
  ## Verify isQueueDrained returns false when in-progress has a markdown file.
  let tmpDir = getTempDir() / "test_loop_system_inprogress"
  createDir(tmpDir / "tickets" / "open")
  createDir(tmpDir / "tickets" / "in-progress")
  createDir(tmpDir / "queue" / "merge" / "pending")
  writeFile(tmpDir / "tickets" / "in-progress" / "0002-test.md", "ticket")
  defer: removeDir(tmpDir)

  doAssert isQueueDrained(tmpDir) == false
  echo "[OK] isQueueDrained returns false when in-progress has a .md file"

proc testQueueNotDrainedPending() =
  ## Verify isQueueDrained returns false when merge pending has a markdown file.
  let tmpDir = getTempDir() / "test_loop_system_pending"
  createDir(tmpDir / "tickets" / "open")
  createDir(tmpDir / "tickets" / "in-progress")
  createDir(tmpDir / "queue" / "merge" / "pending")
  writeFile(tmpDir / "queue" / "merge" / "pending" / "0003-test.md", "ticket")
  defer: removeDir(tmpDir)

  doAssert isQueueDrained(tmpDir) == false
  echo "[OK] isQueueDrained returns false when merge pending has a .md file"

proc testRunFeedbackCommandSuccess() =
  ## Verify runFeedbackCommand returns output from a successful command.
  let output = runFeedbackCommand("/tmp", "echo hello")
  doAssert output.strip() == "hello"
  echo "[OK] runFeedbackCommand returns output containing hello"

proc testRunFeedbackCommandFailure() =
  ## Verify runFeedbackCommand raises on a failing command.
  var raised = false
  try:
    discard runFeedbackCommand("/tmp", "exit 1")
  except IOError:
    raised = true
  doAssert raised, "Expected IOError from failing command"
  echo "[OK] runFeedbackCommand raises on failing command"

proc testReadIterationLogMissing() =
  ## Verify readIterationLog returns empty string when file does not exist.
  let tmpDir = getTempDir() / "test_loop_read_missing"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let content = readIterationLog(tmpDir)
  doAssert content == ""
  echo "[OK] readIterationLog returns empty string when file missing"

proc testReadIterationLogExists() =
  ## Verify readIterationLog returns file content when it exists.
  let tmpDir = getTempDir() / "test_loop_read_exists"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  writeFile(tmpDir / "iteration_log.md", "## Iteration 1\nsome content\n")
  let content = readIterationLog(tmpDir)
  doAssert content == "## Iteration 1\nsome content\n"
  echo "[OK] readIterationLog returns file content when present"

proc testNextIterationNumberEmpty() =
  ## Verify nextIterationNumber returns 1 when no log exists.
  let tmpDir = getTempDir() / "test_loop_next_empty"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let num = nextIterationNumber(tmpDir)
  doAssert num == 1
  echo "[OK] nextIterationNumber returns 1 when no log exists"

proc testNextIterationNumberWithEntries() =
  ## Verify nextIterationNumber returns highest N + 1.
  let tmpDir = getTempDir() / "test_loop_next_entries"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  writeFile(tmpDir / "iteration_log.md", "## Iteration 1\nfoo\n\n## Iteration 3\nbar\n")
  let num = nextIterationNumber(tmpDir)
  doAssert num == 4
  echo "[OK] nextIterationNumber returns 4 after iteration 3"

proc testAppendIterationLogEntry() =
  ## Verify appendIterationLogEntry appends formatted entry.
  let tmpDir = getTempDir() / "test_loop_append"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  appendIterationLogEntry(tmpDir, 1, "output1", "assess1", "strat1", "trade1")
  let content = readIterationLog(tmpDir)
  doAssert "## Iteration 1" in content
  doAssert "output1" in content
  doAssert "assess1" in content
  doAssert "strat1" in content
  doAssert "trade1" in content
  echo "[OK] appendIterationLogEntry writes formatted entry"

proc testAppendIterationLogEntryMultiple() =
  ## Verify multiple appends produce increasing iteration headings.
  let tmpDir = getTempDir() / "test_loop_append_multi"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  appendIterationLogEntry(tmpDir, 1, "out1", "a1", "s1", "t1")
  appendIterationLogEntry(tmpDir, 2, "out2", "a2", "s2", "t2")
  let content = readIterationLog(tmpDir)
  doAssert "## Iteration 1" in content
  doAssert "## Iteration 2" in content
  let num = nextIterationNumber(tmpDir)
  doAssert num == 3
  echo "[OK] multiple appends produce correct iteration numbers"

when isMainModule:
  testQueueDrainedAllEmpty()
  testQueueNotDrainedOpenTicket()
  testQueueNotDrainedInProgress()
  testQueueNotDrainedPending()
  testRunFeedbackCommandSuccess()
  testRunFeedbackCommandFailure()
  testReadIterationLogMissing()
  testReadIterationLogExists()
  testNextIterationNumberEmpty()
  testNextIterationNumberWithEntries()
  testAppendIterationLogEntry()
  testAppendIterationLogEntryMultiple()
