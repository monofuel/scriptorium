import
  std/os,
  ./git_ops

const
  PauseFileName* = "pause"

proc pauseFlagPath*(repoPath: string): string =
  ## Return the full path to the pause flag file.
  result = repoPath / ManagedStateDirName / PauseFileName

proc writePauseFlag*(repoPath: string) =
  ## Create the pause flag file. Idempotent.
  let dir = repoPath / ManagedStateDirName
  createDir(dir)
  writeFile(pauseFlagPath(repoPath), "")

proc removePauseFlag*(repoPath: string) =
  ## Remove the pause flag file. Idempotent — no error if missing.
  let path = pauseFlagPath(repoPath)
  if fileExists(path):
    removeFile(path)

proc isPaused*(repoPath: string): bool =
  ## Return true when the pause flag file exists.
  result = fileExists(pauseFlagPath(repoPath))
