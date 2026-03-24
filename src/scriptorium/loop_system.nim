import
  std/[os, strformat, strutils],
  ./[git_ops, shared_state, ticket_metadata]

const
  IterationLogPath* = "iteration_log.md"

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

proc readIterationLog*(planPath: string): string =
  ## Read the iteration log file content, returning empty string if missing.
  let filePath = planPath / IterationLogPath
  if fileExists(filePath):
    result = readFile(filePath)
  else:
    result = ""

proc nextIterationNumber*(planPath: string): int =
  ## Parse the log to find the highest Iteration N heading and return N+1.
  let content = readIterationLog(planPath)
  if content.len == 0:
    return 1
  var highest = 0
  for line in content.splitLines():
    if line.startsWith("## Iteration "):
      let numStr = line[len("## Iteration ")..^1].strip()
      let num = parseInt(numStr)
      if num > highest:
        highest = num
  result = highest + 1

proc appendIterationLogEntry*(planPath: string, iteration: int, feedbackOutput: string, assessment: string, strategy: string, tradeoffs: string) =
  ## Append a formatted iteration entry to the log file.
  let filePath = planPath / IterationLogPath
  var entry = &"""
## Iteration {iteration}

**Feedback Output:**

{feedbackOutput}

**Assessment:**

{assessment}

**Strategy:**

{strategy}

**Tradeoffs:**

{tradeoffs}

"""
  let existing = readIterationLog(planPath)
  if existing.len > 0 and not existing.endsWith("\n"):
    entry = "\n" & entry
  let f = open(filePath, fmAppend)
  f.write(entry)
  f.close()

proc commitIterationLog*(planPath: string) =
  ## Stage and commit iteration_log.md if it has changed.
  let rc = gitCheck(planPath, "diff", "--quiet", IterationLogPath)
  let untracked = gitCheck(planPath, "ls-files", "--error-unmatch", IterationLogPath)
  if rc == 0 and untracked == 0:
    return
  gitRun(planPath, "add", IterationLogPath)
  gitRun(planPath, "commit", "-m", "chore: update iteration log")
