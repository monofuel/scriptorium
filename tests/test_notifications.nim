import
  std/[os],
  scriptorium/notifications

proc testPostAndConsume() =
  ## Verify posting and consuming notifications works in order.
  let tmpDir = getTempDir() / "test_notifications_post_consume"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  postNotification(tmpDir, "merged", "Ticket #1 merged.")
  sleep(1100)  # Ensure different timestamp.
  postNotification(tmpDir, "stuck", "Ticket #2 is stuck.")

  let messages = consumeNotifications(tmpDir)
  doAssert messages.len == 2
  doAssert messages[0] == "Ticket #1 merged."
  doAssert messages[1] == "Ticket #2 is stuck."

  # Directory should be empty after consume.
  let remaining = consumeNotifications(tmpDir)
  doAssert remaining.len == 0
  echo "[OK] postNotification and consumeNotifications work in order"

proc testConsumeEmpty() =
  ## Verify consuming from nonexistent directory returns empty seq.
  let tmpDir = getTempDir() / "test_notifications_empty"
  let messages = consumeNotifications(tmpDir)
  doAssert messages.len == 0
  echo "[OK] consumeNotifications returns empty for nonexistent directory"

proc testClearNotifications() =
  ## Verify clearNotifications removes all pending notifications.
  let tmpDir = getTempDir() / "test_notifications_clear"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  postNotification(tmpDir, "merged", "Ticket #1 merged.")
  postNotification(tmpDir, "stuck", "Ticket #2 is stuck.")

  clearNotifications(tmpDir)

  let messages = consumeNotifications(tmpDir)
  doAssert messages.len == 0
  echo "[OK] clearNotifications removes all pending notifications"

proc testPostCreatesDirectory() =
  ## Verify postNotification creates the notifications directory.
  let tmpDir = getTempDir() / "test_notifications_create_dir"
  defer: removeDir(tmpDir)

  postNotification(tmpDir, "merged", "Ticket #1 merged.")

  let messages = consumeNotifications(tmpDir)
  doAssert messages.len == 1
  doAssert messages[0] == "Ticket #1 merged."
  echo "[OK] postNotification creates directory when it does not exist"

proc testClearNonexistentDirectory() =
  ## Verify clearNotifications does not raise on nonexistent directory.
  let tmpDir = getTempDir() / "test_notifications_clear_nonexistent"
  clearNotifications(tmpDir)
  echo "[OK] clearNotifications handles nonexistent directory"

when isMainModule:
  testPostAndConsume()
  testConsumeEmpty()
  testClearNotifications()
  testPostCreatesDirectory()
  testClearNonexistentDirectory()
