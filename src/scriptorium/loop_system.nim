import
  std/[os, strformat],
  ./[git_ops, shared_state, ticket_metadata]

proc isQueueDrained*(planPath: string): bool =
  ## Check whether all ticket and merge queues are empty.
  let
    openFiles = listMarkdownFiles(planPath / PlanTicketsOpenDir)
    inProgressFiles = listMarkdownFiles(planPath / PlanTicketsInProgressDir)
    pendingFiles = listMarkdownFiles(planPath / PlanMergeQueuePendingDir)
  result = openFiles.len == 0 and inProgressFiles.len == 0 and pendingFiles.len == 0

proc runFeedbackCommand*(repoPath: string, command: string): string =
  ## Run a shell command synchronously in the given repo directory and return stdout.
  let commandResult = runCommandCapture(repoPath, "sh", @["-c", command], 300_000)
  if commandResult.exitCode != 0:
    let exitCode = commandResult.exitCode
    let output = commandResult.output
    raise newException(IOError, &"Feedback command failed with exit code {exitCode}: {output}")
  result = commandResult.output
