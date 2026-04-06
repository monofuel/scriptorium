import
  std/[algorithm, os, strformat, times]

const
  NotificationsDir = ".scriptorium" / "notifications"

proc notificationsPath(repoPath: string): string =
  ## Return the path to the notifications directory.
  repoPath / NotificationsDir

proc postNotification*(repoPath: string, event: string, message: string) =
  ## Write a notification file for the bot to pick up.
  let dir = notificationsPath(repoPath)
  createDir(dir)
  let timestamp = now().format("yyyyMMdd'T'HHmmss")
  let path = dir / &"{timestamp}_{event}.txt"
  writeFile(path, message)

proc consumeNotifications*(repoPath: string): seq[string] =
  ## Read and delete all pending notification files, in chronological order.
  let dir = notificationsPath(repoPath)
  if not dirExists(dir):
    return @[]
  var files: seq[string] = @[]
  for kind, path in walkDir(dir):
    if kind == pcFile:
      files.add(path)
  files.sort()
  for path in files:
    result.add(readFile(path))
    removeFile(path)

proc clearNotifications*(repoPath: string) =
  ## Delete all pending notifications. Called on bot startup to avoid replaying stale events.
  let dir = notificationsPath(repoPath)
  if not dirExists(dir):
    return
  for kind, path in walkDir(dir):
    if kind == pcFile:
      removeFile(path)
