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

when isMainModule:
  testQueueDrainedAllEmpty()
  testQueueNotDrainedOpenTicket()
  testQueueNotDrainedInProgress()
  testQueueNotDrainedPending()
  testRunFeedbackCommandSuccess()
  testRunFeedbackCommandFailure()
